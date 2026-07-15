`timescale 1ns/1ps

module tb_ql_memory_map_ram;
    reg clk = 1'b0;
    reg reset = 1'b0;
    reg [1:0] ram_config = 2'd0;
    reg bus_req = 1'b1;
    reg [21:0] bus_addr = 22'd0;
    reg [1:0] bus_ds = 2'b00;
    wire ram_req;
    wire qlsd_access;
    wire [15:0] qlsd_address;

    always #5 clk = ~clk;

    ql_memory_map dut (
        .clk(clk), .reset(reset), .ram_config(ram_config),
        .bus_req(bus_req), .bus_we(1'b0), .bus_addr(bus_addr),
        .bus_ds(bus_ds), .bus_wdata(16'd0), .bus_ready(),
        .bus_data_valid(), .bus_data(), .bus_write_done(),
        .rom_is_diagnostic(), .rom_is_dynamic(),
        .boot_vectors_active(1'b0), .boot_ssp(32'd0), .boot_pc(32'd0),
        .dynamic_rom_req(), .dynamic_rom_addr(),
        .dynamic_rom_ready(1'b0), .dynamic_rom_data_valid(1'b0),
        .dynamic_rom_data(16'd0), .mc_stat_wr(), .mc_stat_data(),
        .qlsd_access(qlsd_access), .qlsd_address(qlsd_address),
        .qlsd_dtack(1'b0), .qlsd_data(8'hff),
        .zx8302_wr(), .zx8302_addr(), .zx8302_ds(), .zx8302_wdata(),
        .zx8302_rdata(16'hffff), .zx8302_write_done(1'b0),
        .ram_req(ram_req), .ram_we(), .ram_addr(), .ram_ds(),
        .ram_wdata(), .ram_ready(1'b1), .ram_data_valid(1'b0),
        .ram_data(16'd0), .ram_write_done(1'b0)
    );

    task automatic expect_ram;
        input [1:0] config_value;
        input [23:0] byte_address;
        input expected;
        begin
            ram_config = config_value;
            bus_addr = byte_address[22:1];
            #1;
            if (ram_req !== expected)
                $fatal(1, "RAM config %0d address %h selected=%b expected=%b",
                       config_value, byte_address, ram_req, expected);
        end
    endtask

    initial begin
        // Base 128 KiB RAM is present in every configuration.
        expect_ram(2'd0, 24'h020000, 1'b1);
        expect_ram(2'd0, 24'h03fffe, 1'b1);
        expect_ram(2'd0, 24'h040000, 1'b0);

        // 640 KiB: base 128 KiB plus 512 KiB through $BFFFF.
        expect_ram(2'd1, 24'h040000, 1'b1);
        expect_ram(2'd1, 24'h0bfffe, 1'b1);
        expect_ram(2'd1, 24'h0c0000, 1'b0);

        // 896 KiB: base 128 KiB plus 768 KiB through $FFFFF.
        expect_ram(2'd2, 24'h0c0000, 1'b1);
        expect_ram(2'd2, 24'h0ffffe, 1'b1);
        expect_ram(2'd2, 24'h100000, 1'b0);

        // QLROMEXT uses byte-wide reads, including adjacent even/odd
        // control registers in the QL expansion-ROM window.
        bus_addr = 24'h00fee0 >> 1;
        bus_ds = 2'b01;
        #1;
        if (!qlsd_access || qlsd_address != 16'hfee0)
            $fatal(1, "QL-SD even register decoded as %h", qlsd_address);
        bus_ds = 2'b10;
        #1;
        if (!qlsd_access || qlsd_address != 16'hfee1)
            $fatal(1, "QL-SD odd register decoded as %h", qlsd_address);

        $display("PASS: QL RAM decode matches 128/640/896 KiB configurations");
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
