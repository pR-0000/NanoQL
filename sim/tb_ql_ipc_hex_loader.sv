`timescale 1ns/1ps

module tb_ql_ipc_hex_loader;
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

    reg [7:0] hex_file [0:8191];
    integer hex_length = 0;
    integer writes = 0;
    integer record;
    integer data_index;
    integer checksum;
    integer address;
    integer index;
    integer byte_index;
    integer file_index;
    integer sector_total;

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

    function automatic [7:0] firmware_byte;
        input integer byte_address;
        begin
            firmware_byte =
                byte_address[7:0] ^ {6'd0, byte_address[10:9]};
        end
    endfunction

    task automatic append_character;
        input [7:0] character;
        begin
            hex_file[hex_length] = character;
            hex_length = hex_length + 1;
        end
    endtask

    task automatic append_nibble;
        input [3:0] nibble;
        begin
            append_character(nibble < 10 ? "0" + nibble :
                                           "A" + nibble - 10);
        end
    endtask

    task automatic append_hex_byte;
        input [7:0] value;
        begin
            append_nibble(value[7:4]);
            append_nibble(value[3:0]);
        end
    endtask

    task automatic append_data_record;
        input integer record_address;
        begin
            append_character(":");
            append_hex_byte(8'd16);
            append_hex_byte(record_address[15:8]);
            append_hex_byte(record_address[7:0]);
            append_hex_byte(8'h00);
            checksum = 16 + record_address[15:8] +
                       record_address[7:0];
            for (data_index = 0; data_index < 16;
                 data_index = data_index + 1) begin
                append_hex_byte(firmware_byte(record_address + data_index));
                checksum = checksum +
                           firmware_byte(record_address + data_index);
            end
            append_hex_byte((-checksum) & 8'hff);
            append_character(8'h0d);
            append_character(8'h0a);
        end
    endtask

    always @(posedge clk)
        if (rom_we) begin
            if (rom_addr !== writes[10:0])
                $fatal(1, "Intel HEX IPC address mismatch");
            if (rom_data !== firmware_byte(writes))
                $fatal(1, "Intel HEX IPC data mismatch");
            writes <= writes + 1;
        end

    initial begin
        for (record = 0; record < 128; record = record + 1)
            append_data_record(record * 16);
        append_character(":");
        append_hex_byte(8'h00);
        append_hex_byte(8'h00);
        append_hex_byte(8'h00);
        append_hex_byte(8'h01);
        append_hex_byte(8'hff);
        append_character(8'h0a);

        repeat (3) @(posedge clk);
        reset = 1'b0;
        image_size = hex_length;
        mounted = 1'b1;
        @(posedge clk);
        mounted = 1'b0;

        sector_total = (hex_length + 511) / 512;
        for (index = 0; index < sector_total; index = index + 1) begin
            wait (read_start && sector == index);
            @(negedge clk);
            busy = 1'b1;
            @(negedge clk);
            busy = 1'b0;
            for (byte_index = 0; byte_index < 512;
                 byte_index = byte_index + 1) begin
                file_index = index * 512 + byte_index;
                @(negedge clk);
                byte_addr = byte_index[8:0];
                byte_valid = 1'b1;
                byte_data = file_index < hex_length ?
                            hex_file[file_index] : 8'hff;
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
                   "Intel HEX IPC load failed: loaded=%d failed=%d writes=%0d",
                   loaded, failed, writes);
        $display("PASS: Intel HEX IPC ROM load and checksum validation");
        $finish;
    end
endmodule
