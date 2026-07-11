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

    reg [8:0] rtc_div;
    reg [47:0] rtc;
    reg vblank_d;
    reg vsync_irq;
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

    wire [7:0] irq_pending = {4'b0000, vsync_irq, 3'b000};
    wire [7:0] io_status = {comdata_to_cpu, ipc_busy[0], 6'b000000};

    // Preserve the QL's 68008 IPL wiring while presenting three active-low
    // inputs to fx68k. VBlank forces level 2; otherwise the IPC controls IPL.
    wire [1:0] ql_ipl_n = {ipc_ipl[1] && !vsync_irq, ipc_ipl[0]};
    assign ipl_n = {ql_ipl_n[0], ql_ipl_n[1], ql_ipl_n[0]};
    assign ipc_ready = ipc_transaction_seen && !ipc_busy[0];

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
            microdrive_control <= 8'd0;
            comdata_shift <= 4'b0000;
            ipc_busy <= 2'b11;
            comdata_to_cpu <= 1'b1;
            comctrl_d <= 1'b1;
            ipc_transaction_seen <= 1'b0;
        end else begin
            rtc_div <= rtc_div + 9'd1;
            if (rtc_div == 9'h1ff)
                rtc <= rtc + 48'd1;

            vblank_d <= vblank;
            if (!vblank_d && vblank)
                vsync_irq <= 1'b1;

            comctrl_d <= ipc_comctrl;
            if (!ipc_comctrl && comctrl_d) begin
                comdata_to_cpu <= zx8302_comdata_in;
                comdata_shift <= {1'b1, comdata_shift[3:1]};
                ipc_busy <= {1'b0, ipc_busy[1]};
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
                    if (wdata[3])
                        vsync_irq <= 1'b0;
                end
            end
        end
    end

endmodule
