module ql_zx8302_lite(
    input  wire        clk,
    input  wire        reset,
    input  wire        vblank,
    input  wire [63:0] keyboard_matrix,

    input  wire        write,
    input  wire [1:0]  addr,
    input  wire [1:0]  ds,
    input  wire [15:0] wdata,
    output reg  [15:0] rdata,
    output wire [2:0] ipl_n,
    output wire        ipc_ready
);

    reg [8:0] rtc_div;
    reg [47:0] rtc;
    reg vblank_d;
    reg vsync_irq;
    reg [2:0] irq_mask;
    reg [3:0] ipc_write_data;
    reg [1:0] ipc_busy;
    reg comdata_to_cpu;
    reg [7:0] microdrive_control;

    wire [7:0] irq_pending = {4'b0000, vsync_irq, 3'b000};
    // No IPC is connected yet. Keep COMDATA high and IPC busy asserted so
    // system ROMs wait cleanly instead of consuming a fabricated response.
    wire [7:0] io_status = {comdata_to_cpu, ipc_busy[0], 6'b000000};

    // Level 2 is encoded as active-low IPL[2:0] = 3'b101.
    assign ipl_n = vsync_irq ? 3'b101 : 3'b111;
    assign ipc_ready = 1'b0;

    always @(*) begin
        case (addr)
            2'b00: rdata = rtc[47:32];
            2'b01: rdata = rtc[31:16];
            2'b10: rdata = {io_status, irq_pending};
            default: rdata = 16'hffff;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            rtc_div <= 9'd0;
            rtc <= 48'd0;
            vblank_d <= vblank;
            vsync_irq <= 1'b0;
            irq_mask <= 3'd0;
            ipc_write_data <= 4'hf;
            ipc_busy <= 2'b11;
            comdata_to_cpu <= 1'b1;
            microdrive_control <= 8'd0;
        end else begin
            rtc_div <= rtc_div + 9'd1;
            if (rtc_div == 9'h1ff)
                rtc <= rtc + 48'd1;

            vblank_d <= vblank;
            if (!vblank_d && vblank)
                vsync_irq <= 1'b1;

            if (write) begin
                // Upper byte at 0x18020: microdrive control placeholder.
                if ((addr == 2'b10) && !ds[1])
                    microdrive_control <= wdata[15:8];

                // Lower byte at 0x18003: IPC serial write placeholder.
                if ((addr == 2'b01) && !ds[0]) begin
                    ipc_write_data <= wdata[3:0];
                    ipc_busy <= 2'b11;
                end

                // Lower byte at 0x18021: interrupt mask and acknowledge.
                if ((addr == 2'b10) && !ds[0]) begin
                    irq_mask <= wdata[7:5];
                    if (wdata[3])
                        vsync_irq <= 1'b0;
                end
            end
        end
    end

endmodule
