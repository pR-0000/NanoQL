// Sinclair QL ZX8302 register, interrupt, RTC, and IPC interface.
// Adapted from QL_MiSTer's rtl/zx8302.v.
// Copyright (c) 2015 Till Harbaum
// Copyright (c) 2021 Daniele Terdina
// GPL-3.0-or-later
module ql_zx8302 (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_11m,
    input  wire        ce_bus_n,
    input  wire        vs,
    input  wire [63:0] keyboard_matrix,
    input  wire        ipc_rom_write_enable,
    input  wire [10:0] ipc_rom_write_address,
    input  wire [7:0]  ipc_rom_write_data,
    input  wire        microdrive_gap,
    input  wire        microdrive_rx_ready,
    input  wire        microdrive_tx_full,
    input  wire [7:0]  microdrive_data,
    output wire        microdrive_selected,
    output wire        microdrive_write_enable,
    output wire        microdrive_erase_enable,
    output reg         microdrive_tx_write,
    output reg  [7:0]  microdrive_tx_data,

    input  wire        cpu_read,
    input  wire        cpu_write,
    input  wire [1:0]  cpu_addr,
    input  wire [1:0]  cpu_ds_n,
    input  wire [15:0] cpu_din,
    output reg         cpu_write_done,
    output reg  [15:0] cpu_dout,
    output wire [2:0] ipl_n,
    output wire        ipc_ready,
    output wire        audio
);

    reg [3:0] comdata_reg;
    reg [1:0] ipc_busy;
    reg comdata_to_cpu;
    reg previous_ipc_comctrl;
    reg ipc_transaction_seen;
    reg [7:0] microdrive_control;
    reg [7:0] microdrive_select;
    reg previous_microdrive_clock;
    reg [4:0] irq_ack;
    reg [2:0] irq_mask;
    reg write_pending;
    reg [1:0] pending_addr;
    reg [1:0] pending_ds_n;
    reg [15:0] pending_din;
    reg [7:0] microdrive_receive_data;
    reg previous_microdrive_rx_ready;

    wire ipc_comdata_in = comdata_reg[0];
    wire ipc_comctrl;
    wire ipc_comdata_out;
    wire [1:0] ipc_ipl;
    wire zx8302_comdata_in = ipc_comdata_in && ipc_comdata_out;
    wire ipc_comctrl_falling = !ipc_comctrl && previous_ipc_comctrl;

    ql_ipc_t48 ipc (
        .clk(clk),
        .reset(reset),
        .ce_11m(ce_11m),
        .comdata_in(ipc_comdata_in),
        .keyboard_matrix(keyboard_matrix),
        .rom_write_enable(ipc_rom_write_enable),
        .rom_write_address(ipc_rom_write_address),
        .rom_write_data(ipc_rom_write_data),
        .comctrl(ipc_comctrl),
        .comdata_out(ipc_comdata_out),
        .audio(audio),
        .ipl(ipc_ipl)
    );

    assign microdrive_selected = microdrive_select[0];
    assign microdrive_write_enable = microdrive_control[2];
    assign microdrive_erase_enable = microdrive_control[3];

    reg [5:0] rtc_frame_divider;
    reg [31:0] rtc;
    reg vsync_irq;
    reg gap_irq;
    reg external_irq;
    reg previous_vs;
    reg previous_gap_irq_in;

    wire gap_irq_in = microdrive_gap && irq_mask[0];
    wire [7:0] irq_pending = {
        1'b0,
        microdrive_select == 8'd0,
        rtc[0],
        external_irq,
        vsync_irq,
        2'b00,
        gap_irq
    };
    wire [7:0] io_status = {
        comdata_to_cpu,
        ipc_busy[0],
        2'b00,
        microdrive_gap,
        microdrive_rx_ready,
        microdrive_tx_full,
        1'b0
    };

    // The QL's 68008 ties IPL0 and IPL2 together. Peripheral IRQs force
    // level 2 while the 8049 controls both logical interrupt lines.
    wire [1:0] ql_ipl_n = {
        ipc_ipl[1] && (irq_pending[4:0] == 5'd0),
        ipc_ipl[0]
    };
    assign ipl_n = {ql_ipl_n[0], ql_ipl_n[1], ql_ipl_n[0]};
    assign ipc_ready = ipc_transaction_seen && !ipc_busy[0];

    always @(*) begin
        case (cpu_addr)
            2'b00: cpu_dout = rtc[31:16];
            2'b01: cpu_dout = rtc[15:0];
            2'b10: cpu_dout = {io_status, irq_pending};
            2'b11: cpu_dout = {
                microdrive_receive_data, microdrive_receive_data
            };
            default: cpu_dout = 16'h0000;
        endcase
    end

    // The memory map emits one pulse per accepted 68008 register write. Hold
    // it until the negative CPU phase, matching QL_MiSTer's cen sampling.
    // A simultaneous COMCTRL edge has priority in the original module; defer
    // the CPU write by one phase so neither side of the serial link is lost.
    always @(posedge clk) begin
        if (reset) begin
            comdata_reg <= 4'b0000;
            ipc_busy <= 2'b11;
            comdata_to_cpu <= 1'b1;
            previous_ipc_comctrl <= 1'b1;
            ipc_transaction_seen <= 1'b0;
            microdrive_control <= 8'd0;
            irq_ack <= 5'd0;
            irq_mask <= 3'd0;
            write_pending <= 1'b0;
            pending_addr <= 2'd0;
            pending_ds_n <= 2'b11;
            pending_din <= 16'd0;
            microdrive_receive_data <= 8'd0;
            previous_microdrive_rx_ready <= 1'b0;
            microdrive_tx_write <= 1'b0;
            microdrive_tx_data <= 8'd0;
            cpu_write_done <= 1'b0;
        end else begin
            irq_ack <= 5'd0;
            microdrive_tx_write <= 1'b0;
            cpu_write_done <= 1'b0;

            if (cpu_write) begin
                write_pending <= 1'b1;
                pending_addr <= cpu_addr;
                pending_ds_n <= cpu_ds_n;
                pending_din <= cpu_din;
            end

            // The physical ZX8302 owns a receive holding register. Capture
            // the byte when its RX-ready signal rises, independently of when
            // or how quickly the 68000 polls the status register. Capturing on
            // the CPU status read caused the following data read to race this
            // register in accelerated 16/24 MHz modes.
            if (microdrive_rx_ready && !previous_microdrive_rx_ready)
                microdrive_receive_data <= microdrive_data;
            previous_microdrive_rx_ready <= microdrive_rx_ready;

            if (ce_bus_n && write_pending && !ipc_comctrl_falling) begin
                // Preserve a newly arriving write when the previous one is
                // committed on this same FPGA clock.
                write_pending <= cpu_write;
                cpu_write_done <= 1'b1;

                if (!pending_ds_n[1] && (pending_addr == 2'b10))
                    microdrive_control <= pending_din[15:8];

                if (!pending_ds_n[0] && (pending_addr == 2'b01)) begin
                    comdata_reg <= pending_din[3:0];
                    ipc_busy <= 2'b11;
                    ipc_transaction_seen <= 1'b1;
                end

                if (!pending_ds_n[0] && (pending_addr == 2'b10)) begin
                    irq_mask <= pending_din[7:5];
                    irq_ack <= pending_din[4:0];
                end

                // $18022/$18023 is the shared serial transmit register. In
                // Microdrive mode QDOS writes one byte only after status bit
                // 1 reports that the previous byte has left the ZX8302.
                if (pending_addr == 2'b11) begin
                    if (!pending_ds_n[1]) begin
                        microdrive_tx_data <= pending_din[15:8];
                        microdrive_tx_write <= 1'b1;
                    end else if (!pending_ds_n[0]) begin
                        microdrive_tx_data <= pending_din[7:0];
                        microdrive_tx_write <= 1'b1;
                    end
                end
            end

            if (ipc_comctrl_falling) begin
                comdata_to_cpu <= zx8302_comdata_in;
                comdata_reg <= {1'b1, comdata_reg[3:1]};
                ipc_busy <= {1'b0, ipc_busy[1]};
            end
            previous_ipc_comctrl <= ipc_comctrl;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            previous_vs <= vs;
            vsync_irq <= 1'b0;
        end else begin
            previous_vs <= vs;
            if (irq_ack[3])
                vsync_irq <= 1'b0;
            else if (!previous_vs && vs)
                vsync_irq <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            previous_gap_irq_in <= 1'b0;
            gap_irq <= 1'b0;
        end else begin
            previous_gap_irq_in <= gap_irq_in;
            if (irq_ack[0])
                gap_irq <= 1'b0;
            else if (!previous_gap_irq_in && gap_irq_in)
                gap_irq <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset)
            external_irq <= 1'b0;
        else if (irq_ack[4])
            external_irq <= 1'b0;
    end

    always @(posedge clk) begin
        if (reset) begin
            previous_microdrive_clock <= 1'b0;
            microdrive_select <= 8'd0;
        end else begin
            previous_microdrive_clock <= microdrive_control[1];
            if (previous_microdrive_clock && !microdrive_control[1])
                microdrive_select <= {
                    microdrive_select[6:0], microdrive_control[0]
                };
        end
    end

    // Until a companion RTC timestamp is connected, derive one QL second
    // from the PAL frame cadence while preserving the ZX8302 register format.
    always @(posedge clk) begin
        if (reset) begin
            rtc_frame_divider <= 6'd0;
            rtc <= 32'd0;
        end else if (!previous_vs && vs) begin
            if (rtc_frame_divider == 6'd49) begin
                rtc_frame_divider <= 6'd0;
                rtc <= rtc + 32'd1;
            end else begin
                rtc_frame_divider <= rtc_frame_divider + 6'd1;
            end
        end
    end
endmodule
