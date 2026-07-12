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
    output wire [2:0]  ipl_n,
    output wire        ipc_ready
);

    reg [5:0] rtc_frame_div;
    reg [31:0] rtc;
    reg vblank_d;
    reg vsync_irq;
    reg gap_irq;
    reg gap_irq_in_d;
    reg [2:0] irq_mask;
    reg [7:0] microdrive_control;

    reg [3:0] comdata_shift;
    reg [1:0] ipc_busy;
    reg comdata_to_cpu;
    reg comctrl_d;
    reg ipc_transaction_seen;

    wire ipc_comdata_in = comdata_shift[0];
    wire ipc_comctrl;
    wire ipc_comdata_out;
    wire ipc_audio;
    wire [1:0] ipc_ipl;
    wire zx8302_comdata_in = ipc_comdata_in && ipc_comdata_out;

    ql_ipc_t48 ipc (
        .clk(clk),
        .reset(reset),
        .comdata_in(ipc_comdata_in),
        .keyboard_matrix(keyboard_matrix),
        .comctrl(ipc_comctrl),
        .comdata_out(ipc_comdata_out),
        .audio(ipc_audio),
        .ipl(ipc_ipl)
    );

    // No Microdrive image is mounted yet. Real QL hardware and the MiSTer
    // implementation report a permanent GAP in that state, no receive byte,
    // and no transmit-empty event.
    wire mdv_gap = 1'b1;
    wire gap_irq_in = mdv_gap && irq_mask[0];
    wire [7:0] irq_pending = {
        1'b0, 1'b1, rtc[0], 1'b0, vsync_irq, 2'b00, gap_irq
    };
    wire [7:0] io_status = {
        comdata_to_cpu, ipc_busy[0], 2'b00, mdv_gap, 3'b000
    };

    // Keyboard input is polled from VBlank. The no-cartridge GAP interrupt is
    // also implemented so QDOS can terminate its Microdrive boot probe.
    assign ipl_n = (vsync_irq || gap_irq) ? 3'b101 : 3'b111;
    assign ipc_ready = ipc_transaction_seen && !ipc_busy[0];

    always @(*) begin
        case (addr)
            2'b00: rdata = rtc[31:16];
            2'b01: rdata = rtc[15:0];
            2'b10: rdata = {io_status, irq_pending};
            default: rdata = 16'hffff;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            rtc_frame_div <= 6'd0;
            rtc <= 32'd0;
            vblank_d <= vblank;
            vsync_irq <= 1'b0;
            gap_irq <= 1'b0;
            gap_irq_in_d <= 1'b0;
            irq_mask <= 3'd0;
            microdrive_control <= 8'd0;
            comdata_shift <= 4'b0000;
            ipc_busy <= 2'b11;
            comdata_to_cpu <= 1'b1;
            comctrl_d <= 1'b1;
            ipc_transaction_seen <= 1'b0;
        end else begin
            vblank_d <= vblank;
            gap_irq_in_d <= gap_irq_in;
            if (!gap_irq_in_d && gap_irq_in)
                gap_irq <= 1'b1;

            if (!vblank_d && vblank) begin
                vsync_irq <= 1'b1;
                if (rtc_frame_div == 6'd49) begin
                    rtc_frame_div <= 6'd0;
                    rtc <= rtc + 32'd1;
                end else begin
                    rtc_frame_div <= rtc_frame_div + 6'd1;
                end
            end

            if (write) begin
                if ((addr == 2'b10) && !ds[1])
                    microdrive_control <= wdata[15:8];

                if ((addr == 2'b01) && !ds[0]) begin
                    comdata_shift <= wdata[3:0];
                    ipc_busy <= 2'b11;
                    ipc_transaction_seen <= 1'b1;
                end

                if ((addr == 2'b10) && !ds[0]) begin
                    irq_mask <= wdata[7:5];
                    if (wdata[0])
                        gap_irq <= 1'b0;
                    if (wdata[3])
                        vsync_irq <= 1'b0;
                end
            end

            // The IPC clocks the serial link on COMCTRL's falling edge. Keep
            // this after CPU writes to reproduce the ZX8302/MiST priority when
            // both events happen during the same FPGA clock cycle.
            comctrl_d <= ipc_comctrl;
            if (!ipc_comctrl && comctrl_d) begin
                comdata_to_cpu <= zx8302_comdata_in;
                comdata_shift <= {1'b1, comdata_shift[3:1]};
                ipc_busy <= {1'b0, ipc_busy[1]};
            end
        end
    end

endmodule
