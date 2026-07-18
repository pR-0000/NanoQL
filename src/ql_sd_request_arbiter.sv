// Serialize ROM, QL-SD, and Microdrive accesses to FPGA Companion's
// edge-triggered SD image interface.
module ql_sd_request_arbiter (
    input  wire        clk,
    input  wire        reset,

    input  wire        rom_read_start,
    input  wire [31:0] rom_sector,
    input  wire        qlsd_read_start,
    input  wire        qlsd_write_start,
    input  wire [31:0] qlsd_sector,
    input  wire        mdv_read_start,
    input  wire [31:0] mdv_sector,

    input  wire        sd_busy,
    input  wire        sd_done,
    output reg  [7:0]  sd_read_start,
    output reg  [7:0]  sd_write_start,
    output reg  [31:0] sd_sector
);

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_ASSERT = 2'd1;
    localparam [1:0] ST_WAIT   = 2'd2;
    localparam [1:0] ST_GUARD  = 2'd3;

    reg [1:0] state;
    reg [2:0] owner;
    reg owner_write;

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            owner <= 3'd0;
            owner_write <= 1'b0;
            sd_read_start <= 8'd0;
            sd_write_start <= 8'd0;
            sd_sector <= 32'd0;
        end else begin
            sd_read_start <= 8'd0;
            sd_write_start <= 8'd0;

            case (state)
                ST_IDLE: begin
                    // Match sd_card.v's source priority exactly.
                    if (rom_read_start) begin
                        owner <= 3'd0;
                        owner_write <= 1'b0;
                        sd_sector <= rom_sector;
                        state <= ST_ASSERT;
                    end else if (qlsd_read_start || qlsd_write_start) begin
                        owner <= 3'd1;
                        owner_write <= qlsd_write_start;
                        sd_sector <= qlsd_sector;
                        state <= ST_ASSERT;
                    end else if (mdv_read_start) begin
                        owner <= 3'd2;
                        owner_write <= 1'b0;
                        sd_sector <= mdv_sector;
                        state <= ST_ASSERT;
                    end
                end

                ST_ASSERT: begin
                    if (owner_write)
                        sd_write_start[owner] <= 1'b1;
                    else
                        sd_read_start[owner] <= 1'b1;
                    if (sd_busy) begin
                        sd_read_start <= 8'd0;
                        sd_write_start <= 8'd0;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (sd_done)
                        state <= ST_GUARD;
                end

                // Keep start_any low for a complete cycle so sd_card.v sees
                // a fresh edge even when another client has waited throughout
                // the preceding transfer.
                ST_GUARD: state <= ST_IDLE;

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
