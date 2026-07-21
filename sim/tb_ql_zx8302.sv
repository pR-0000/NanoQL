`timescale 1ns/1ps

module tb_ql_zx8302;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    reg ce_bus_n = 1'b0;
    reg cpu_read = 1'b0;
    reg cpu_write = 1'b0;
    reg [1:0] cpu_addr = 2'd0;
    reg [1:0] cpu_ds_n = 2'b11;
    reg [15:0] cpu_din = 16'd0;
    wire cpu_write_done;
    wire [15:0] cpu_dout;
    wire audio;
    reg microdrive_rx_ready = 1'b0;
    reg [7:0] microdrive_data = 8'd0;

    ql_zx8302 dut (
        .clk(clk), .reset(reset), .ce_11m(1'b0),
        .ce_bus_n(ce_bus_n), .vs(1'b0), .keyboard_matrix(64'd0),
        .microdrive_gap(1'b1), .microdrive_rx_ready(microdrive_rx_ready),
        .microdrive_tx_full(1'b0), .microdrive_data(microdrive_data),
        .microdrive_selected(), .microdrive_write_enable(),
        .microdrive_erase_enable(), .microdrive_tx_write(),
        .microdrive_tx_data(),
        .cpu_read(cpu_read), .cpu_write(cpu_write), .cpu_addr(cpu_addr),
        .cpu_ds_n(cpu_ds_n), .cpu_din(cpu_din),
        .cpu_write_done(cpu_write_done),
        .cpu_dout(cpu_dout),
        .ipl_n(), .ipc_ready(), .audio(audio)
    );

    task automatic pulse_write;
        input [1:0] address;
        input [1:0] ds_n;
        input [15:0] data;
        begin
            @(negedge clk);
            cpu_addr = address;
            cpu_ds_n = ds_n;
            cpu_din = data;
            cpu_write = 1'b1;
            @(negedge clk);
            cpu_write = 1'b0;
        end
    endtask

    task automatic pulse_bus_phase;
        begin
            @(negedge clk);
            ce_bus_n = 1'b1;
            @(negedge clk);
            ce_bus_n = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;

        // A status read that observes RX ready must latch its corresponding
        // byte for the later Microdrive data-register read.
        @(negedge clk);
        cpu_addr = 2'b10;
        cpu_ds_n = 2'b01;
        microdrive_data = 8'ha5;
        microdrive_rx_ready = 1'b1;
        cpu_read = 1'b1;
        @(negedge clk);
        cpu_read = 1'b0;
        microdrive_rx_ready = 1'b0;
        microdrive_data = 8'h5a;
        cpu_addr = 2'b11;
        #1;
        if (cpu_dout !== 16'ha5a5)
            $fatal(1, "ZX8302 did not retain the observed Microdrive byte");

        // Queue one IPC frame, then make its commit phase coincide with a
        // COMCTRL falling edge. The frame must remain pending.
        pulse_write(2'b01, 2'b10, 16'h000e);
        @(negedge clk);
        force dut.ipc.comctrl = 1'b0;
        ce_bus_n = 1'b1;
        @(negedge clk);
        ce_bus_n = 1'b0;
        release dut.ipc.comctrl;
        repeat (2) @(posedge clk);

        if (!dut.write_pending)
            $fatal(1, "ZX8302 lost a write during a COMCTRL collision");
        if (cpu_write_done)
            $fatal(1, "ZX8302 acknowledged a write during a collision");

        pulse_bus_phase();
        if (!cpu_write_done)
            $fatal(1, "ZX8302 did not acknowledge the committed write");
        repeat (2) @(posedge clk);
        if (dut.write_pending)
            $fatal(1, "ZX8302 did not commit the deferred write");
        if (dut.comdata_reg !== 4'he)
            $fatal(1, "ZX8302 committed %h instead of the queued frame",
                   dut.comdata_reg);

        // The even Microdrive data register uses the upper byte lane.
        pulse_write(2'b11, 2'b01, 16'h5a00);
        pulse_bus_phase();
        if (!dut.microdrive_tx_write || dut.microdrive_tx_data != 8'h5a)
            $fatal(1, "ZX8302 did not emit the Microdrive TX byte");

        dut.ipc.audio_test = 1'b1;
        #1;
        if (audio !== 1'b1)
            $fatal(1, "ZX8302 did not expose IPC audio");

        $display("PASS: ZX8302 phase sampling and COMCTRL collision");
        $finish;
    end
endmodule

module ql_ipc_t48 (
    input wire clk,
    input wire reset,
    input wire ce_11m,
    input wire comdata_in,
    input wire [63:0] keyboard_matrix,
    output reg comctrl = 1'b1,
    output wire comdata_out,
    output wire audio,
    output wire [1:0] ipl
);
    reg audio_test = 1'b0;
    assign comdata_out = 1'b1;
    assign audio = audio_test;
    assign ipl = 2'b11;
endmodule
