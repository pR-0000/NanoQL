`timescale 1ns/1ps

module tb_ql_zx8302_bus;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    reg [23:0] cpu_addr = 24'd0;
    reg [15:0] cpu_data_out = 16'd0;
    wire [15:0] cpu_data_in;
    reg cpu_as_n = 1'b1;
    reg cpu_rw = 1'b1;
    reg cpu_uds_n = 1'b1;
    reg cpu_lds_n = 1'b1;
    reg cpu_iack = 1'b0;
    wire cpu_dtack_n;

    wire bus_req;
    wire bus_we;
    wire [21:0] bus_addr;
    wire [1:0] bus_ds;
    wire [15:0] bus_wdata;
    wire bus_ready;
    wire bus_data_valid;
    wire [15:0] bus_data;
    wire bus_write_done;
    reg zx8302_write_done = 1'b0;
    wire zx8302_wr;
    integer write_pulses = 0;

    ql_cpu_bus_bridge bridge (
        .clk(clk), .reset(reset), .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out), .cpu_data_in(cpu_data_in),
        .cpu_as_n(cpu_as_n), .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n), .cpu_lds_n(cpu_lds_n),
        .cpu_iack(cpu_iack),
        .cpu_dtack_n(cpu_dtack_n), .timing_delay(1'b0),
        .ce_bus_p(1'b1), .system_req(bus_req), .system_we(bus_we),
        .system_addr(bus_addr), .system_ds(bus_ds),
        .system_wdata(bus_wdata), .system_ready(bus_ready),
        .system_data_valid(bus_data_valid), .system_data(bus_data),
        .system_write_done(bus_write_done)
    );

    ql_memory_map map (
        .clk(clk), .reset(reset), .bus_req(bus_req), .bus_we(bus_we),
        .ram_config(2'd0),
        .bus_addr(bus_addr), .bus_ds(bus_ds), .bus_wdata(bus_wdata),
        .bus_ready(bus_ready), .bus_data_valid(bus_data_valid),
        .bus_data(bus_data), .bus_write_done(bus_write_done),
        .rom_is_diagnostic(), .rom_is_dynamic(),
        .dynamic_rom_req(), .dynamic_rom_addr(),
        .dynamic_rom_ready(1'b0), .dynamic_rom_data_valid(1'b0),
        .dynamic_rom_data(16'd0), .mc_stat_wr(), .mc_stat_data(),
        .qlsd_access(), .qlsd_address(), .qlsd_dtack(1'b0),
        .qlsd_data(8'hff),
        .qsound_present(1'b0), .qsound_access(),
        .qsound_ready(1'b1), .qsound_data_valid(1'b0),
        .qsound_data(16'hffff), .qsound_write_done(1'b0),
        .zx8302_wr(zx8302_wr), .zx8302_addr(), .zx8302_ds(),
        .zx8302_wdata(), .zx8302_rdata(16'hffff),
        .zx8302_write_done(zx8302_write_done),
        .ram_req(), .ram_we(), .ram_addr(), .ram_ds(), .ram_wdata(),
        .ram_ready(1'b0), .ram_data_valid(1'b0), .ram_data(16'd0),
        .ram_write_done(1'b0)
    );

    always @(posedge clk)
        if (zx8302_wr)
            write_pulses <= write_pulses + 1;

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;

        // An interrupt acknowledge is terminated by VPA, never by the
        // memory bridge. Both data strobes are active on a real 68000 IACK.
        @(negedge clk);
        cpu_iack = 1'b1;
        cpu_uds_n = 1'b0;
        cpu_lds_n = 1'b0;
        cpu_as_n = 1'b0;
        repeat (4) @(posedge clk);
        if (bus_req)
            $fatal(1, "IACK was incorrectly decoded as a memory request");
        if (!cpu_dtack_n)
            $fatal(1, "IACK was incorrectly terminated with DTACK");

        @(negedge clk);
        cpu_iack = 1'b0;
        cpu_as_n = 1'b1;
        cpu_uds_n = 1'b1;
        cpu_lds_n = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        cpu_addr = 24'h018003;
        cpu_data_out = 16'h000e;
        cpu_rw = 1'b0;
        cpu_lds_n = 1'b0;
        cpu_as_n = 1'b0;

        repeat (8) @(posedge clk);
        if (!cpu_dtack_n)
            $fatal(1, "68008 write was acknowledged before ZX8302 commit");
        if (write_pulses != 1)
            $fatal(1, "memory map emitted %0d ZX8302 write pulses", write_pulses);

        @(negedge clk);
        zx8302_write_done = 1'b1;
        @(negedge clk);
        zx8302_write_done = 1'b0;
        repeat (2) @(posedge clk);
        if (cpu_dtack_n)
            $fatal(1, "68008 write was not acknowledged after ZX8302 commit");

        cpu_as_n = 1'b1;
        cpu_rw = 1'b1;
        cpu_lds_n = 1'b1;
        repeat (2) @(posedge clk);
        if (!cpu_dtack_n)
            $fatal(1, "DTACK remained asserted after the bus cycle");

        $display("PASS: ZX8302 write completion reaches 68008 DTACK");
        $finish;
    end
endmodule

module ql_boot_rom (
    input wire [14:0] word_addr,
    output wire [15:0] data,
    output wire is_diagnostic,
    output wire is_dynamic
);
    assign data = 16'hffff;
    assign is_diagnostic = 1'b0;
    assign is_dynamic = 1'b1;
endmodule
