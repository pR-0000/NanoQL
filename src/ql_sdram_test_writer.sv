module ql_sdram_test_writer(
    input  wire        clk,
    input  wire        reset,
    input  wire        init_done,
    input  wire        frame_pulse,

    output wire        req,
    output wire        we,
    output wire [21:0] addr,
    output wire [1:0]  ds,
    output wire [15:0] wdata,
    input  wire        ready
);

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_RESTORE = 2'd1;
    localparam [1:0] ST_DRAW    = 2'd2;

    localparam [21:0] SCREEN_BASE = 22'h010000;
    localparam [7:0] MARKER_Y = 8'd130;

    reg [1:0] state;
    reg [5:0] marker_word;

    wire [5:0] next_word = marker_word + 6'd1;
    wire [13:0] restore_word_addr = {MARKER_Y, marker_word};
    wire [13:0] draw_word_addr = {MARKER_Y, next_word};
    wire [15:0] restore_data;

    ql_test_pattern restore_pattern (
        .mode8(1'b0),
        .word_addr(restore_word_addr),
        .data(restore_data)
    );

    assign req = (state != ST_IDLE);
    assign we = 1'b1;
    assign ds = 2'b00;
    assign addr = SCREEN_BASE + {8'd0,
                                 (state == ST_DRAW) ? draw_word_addr : restore_word_addr};
    assign wdata = (state == ST_DRAW) ? 16'h00ff : restore_data;

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            marker_word <= 6'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (init_done && frame_pulse)
                        state <= ST_RESTORE;
                end

                ST_RESTORE: begin
                    if (ready)
                        state <= ST_DRAW;
                end

                default: begin
                    if (ready) begin
                        marker_word <= next_word;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
