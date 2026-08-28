module ql_video_snapshot #(
    parameter [14:0] FRAME_WORDS = 15'h4000,
    parameter [21:0] SNAPSHOT_BASE_0 = 22'h3f0000,
    parameter [21:0] SNAPSHOT_BASE_1 = 22'h3f4000
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        native_frame,
    input  wire        membase,
    input  wire        scanout_buffer_select,

    output reg         snapshot_valid,
    output reg         snapshot_buffer_select,
    output wire [21:0] snapshot_base,

    output wire        req,
    output wire        we,
    output wire [21:0] addr,
    output wire [1:0]  ds,
    output wire [15:0] wdata,
    input  wire        ready,
    input  wire        data_valid,
    input  wire [15:0] rdata,
    input  wire        write_done
);

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_READ_REQ   = 4'd1;
    localparam [3:0] ST_READ_WAIT  = 4'd2;
    localparam [3:0] ST_READ_GAP   = 4'd3;
    localparam [3:0] ST_WRITE_REQ  = 4'd4;
    localparam [3:0] ST_WRITE_WAIT = 4'd5;
    localparam [3:0] ST_WRITE_GAP  = 4'd6;

    localparam [21:0] QL_SCREEN_BASE_0 = 22'h010000;
    localparam [21:0] QL_SCREEN_BASE_1 = 22'h014000;

    reg [3:0] state;
    reg capture_pending;
    reg observed_membase;
    reg captured_membase;
    reg target_buffer_select;
    reg [14:0] word_index;
    reg [15:0] copy_word;

    wire [21:0] source_base = captured_membase ?
                              QL_SCREEN_BASE_1 : QL_SCREEN_BASE_0;
    wire [21:0] target_base = target_buffer_select ?
                              SNAPSHOT_BASE_1 : SNAPSHOT_BASE_0;
    wire target_is_free = !snapshot_valid ||
                          (scanout_buffer_select == snapshot_buffer_select);

    assign snapshot_base = snapshot_buffer_select ?
                           SNAPSHOT_BASE_1 : SNAPSHOT_BASE_0;
    assign req = (state == ST_READ_REQ) || (state == ST_WRITE_REQ);
    assign we = state == ST_WRITE_REQ;
    assign addr = we ? target_base + word_index : source_base + word_index;
    assign ds = 2'b00;
    assign wdata = copy_word;

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            capture_pending <= 1'b1;
            observed_membase <= 1'b0;
            captured_membase <= 1'b0;
            target_buffer_select <= 1'b0;
            snapshot_valid <= 1'b0;
            snapshot_buffer_select <= 1'b0;
            word_index <= 15'd0;
            copy_word <= 16'd0;
        end else begin
            // Capture at native frame boundaries for single-buffer software,
            // and immediately after MC_STAT page changes for double buffering.
            if (native_frame || (membase != observed_membase)) begin
                capture_pending <= 1'b1;
                observed_membase <= membase;
            end

            case (state)
                ST_IDLE: begin
                    if (enable && capture_pending && target_is_free) begin
                        captured_membase <= membase;
                        target_buffer_select <= snapshot_valid ?
                                                ~snapshot_buffer_select : 1'b0;
                        word_index <= 15'd0;
                        capture_pending <= 1'b0;
                        state <= ST_READ_REQ;
                    end
                end

                ST_READ_REQ: begin
                    if (!enable) begin
                        capture_pending <= 1'b1;
                        state <= ST_IDLE;
                    end else if (ready)
                        state <= ST_READ_WAIT;
                end

                ST_READ_WAIT: begin
                    if (data_valid) begin
                        if (!enable || (membase != captured_membase)) begin
                            capture_pending <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            copy_word <= rdata;
                            state <= ST_READ_GAP;
                        end
                    end
                end

                ST_READ_GAP: begin
                    if (!enable) begin
                        capture_pending <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_WRITE_REQ;
                    end
                end

                ST_WRITE_REQ: begin
                    if (!enable) begin
                        capture_pending <= 1'b1;
                        state <= ST_IDLE;
                    end else if (ready)
                        state <= ST_WRITE_WAIT;
                end

                ST_WRITE_WAIT: begin
                    if (write_done) begin
                        if (!enable || (membase != captured_membase)) begin
                            capture_pending <= 1'b1;
                            state <= ST_IDLE;
                        end else if (word_index == FRAME_WORDS - 1'b1) begin
                            snapshot_buffer_select <= target_buffer_select;
                            snapshot_valid <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            word_index <= word_index + 15'd1;
                            state <= ST_WRITE_GAP;
                        end
                    end
                end

                ST_WRITE_GAP: begin
                    if (!enable) begin
                        capture_pending <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_READ_REQ;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
