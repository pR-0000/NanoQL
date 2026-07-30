`timescale 1ns/1ps

module tb_ql_ipc_rom_loader;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    reg mounted = 1'b0;
    reg [63:0] image_size = 64'd0;
    reg busy = 1'b0;
    reg done = 1'b0;
    reg byte_valid = 1'b0;
    reg [8:0] byte_addr = 9'd0;
    reg [7:0] byte_data = 8'd0;
    wire read_start;
    wire [31:0] sector;
    wire rom_we;
    wire [10:0] rom_addr;
    wire [7:0] rom_data;
    wire loading;
    wire loaded;
    wire failed;
    integer index;
    integer byte_index;
    integer writes = 0;

    ql_ipc_rom_loader dut (
        .clk(clk), .reset(reset), .enable(1'b1),
        .image_mounted(mounted), .image_size(image_size),
        .sd_read_start(read_start), .sd_sector(sector),
        .sd_busy(busy), .sd_done(done),
        .sd_byte_valid(byte_valid), .sd_byte_addr(byte_addr),
        .sd_byte(byte_data), .rom_write_enable(rom_we),
        .rom_write_address(rom_addr), .rom_write_data(rom_data),
        .loading(loading), .loaded(loaded), .failed(failed),
        .sector_progress()
    );

    always @(posedge clk)
        if (rom_we) begin
            if (rom_addr !== writes[10:0])
                $fatal(1, "IPC ROM address mismatch");
            if (rom_data !== (writes[7:0] ^ {6'd0, writes[10:9]}))
                $fatal(1, "IPC ROM data mismatch");
            writes <= writes + 1;
        end

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        image_size = 64'd2048;
        mounted = 1'b1;
        @(posedge clk);
        mounted = 1'b0;

        for (index = 0; index < 4; index = index + 1) begin
            wait (read_start && sector == index);
            @(negedge clk);
            busy = 1'b1;
            @(negedge clk);
            busy = 1'b0;
            for (byte_index = 0; byte_index < 512; byte_index = byte_index + 1) begin
                @(negedge clk);
                byte_addr = byte_index[8:0];
                byte_valid = 1'b1;
                byte_data = byte_index[7:0] ^ index[7:0];
            end
            @(negedge clk);
            byte_valid = 1'b0;
            done = 1'b1;
            @(negedge clk);
            done = 1'b0;
        end

        wait (loaded || failed);
        repeat (2) @(posedge clk);
        if (failed || !loaded || writes != 2048)
            $fatal(1, "IPC ROM load failed: loaded=%d failed=%d writes=%0d",
                   loaded, failed, writes);
        $display("PASS: dynamic 2 KiB IPC ROM load");
        $finish;
    end
endmodule
