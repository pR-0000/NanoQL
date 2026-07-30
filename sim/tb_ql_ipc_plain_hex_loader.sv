`timescale 1ns/1ps

module tb_ql_ipc_plain_hex_loader;
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
    wire loaded;
    wire failed;
    integer index;
    integer byte_index;
    integer file_index;
    integer firmware_index;
    integer writes = 0;
    reg [7:0] firmware_value;

    ql_ipc_rom_loader dut (
        .clk(clk), .reset(reset), .enable(1'b1),
        .image_mounted(mounted), .image_size(image_size),
        .sd_read_start(read_start), .sd_sector(sector),
        .sd_busy(busy), .sd_done(done),
        .sd_byte_valid(byte_valid), .sd_byte_addr(byte_addr),
        .sd_byte(byte_data), .rom_write_enable(rom_we),
        .rom_write_address(rom_addr), .rom_write_data(rom_data),
        .loading(), .loaded(loaded), .failed(failed),
        .sector_progress()
    );

    function automatic [7:0] firmware_byte;
        input integer address;
        begin
            firmware_byte = address[7:0] ^ {6'd0, address[10:9]};
        end
    endfunction

    function automatic [7:0] hex_character;
        input [3:0] nibble;
        begin
            hex_character = nibble < 10 ? "0" + nibble :
                                          "A" + nibble - 10;
        end
    endfunction

    always @(posedge clk)
        if (rom_we) begin
            if (rom_addr !== writes[10:0])
                $fatal(1, "Plain HEX IPC address mismatch");
            if (rom_data !== firmware_byte(writes))
                $fatal(1, "Plain HEX IPC data mismatch");
            writes <= writes + 1;
        end

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        image_size = 64'd8192;
        mounted = 1'b1;
        @(posedge clk);
        mounted = 1'b0;

        for (index = 0; index < 16; index = index + 1) begin
            wait (read_start && sector == index);
            @(negedge clk);
            busy = 1'b1;
            @(negedge clk);
            busy = 1'b0;
            for (byte_index = 0; byte_index < 512;
                 byte_index = byte_index + 1) begin
                file_index = index * 512 + byte_index;
                firmware_index = file_index / 4;
                firmware_value = firmware_byte(firmware_index);
                @(negedge clk);
                byte_addr = byte_index[8:0];
                byte_valid = 1'b1;
                case (file_index % 4)
                    0: byte_data = hex_character(firmware_value[7:4]);
                    1: byte_data = hex_character(firmware_value[3:0]);
                    2: byte_data = 8'h0d;
                    default: byte_data = 8'h0a;
                endcase
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
            $fatal(1,
                   "Plain HEX IPC load failed: loaded=%d failed=%d writes=%0d",
                   loaded, failed, writes);
        $display("PASS: whitespace-separated plain HEX IPC ROM load");
        $finish;
    end
endmodule
