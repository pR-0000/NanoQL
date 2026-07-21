`timescale 1ns/1ps

module tb_ql_qsound_card;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg core_reset = 1'b1;
    always #5 clk = ~clk;

    reg image_mounted = 1'b0;
    reg [63:0] image_size = 64'd0;
    wire sd_read_start;
    wire [31:0] sd_sector;
    reg sd_busy = 1'b0;
    reg sd_done = 1'b0;
    reg sd_byte_valid = 1'b0;
    reg [8:0] sd_byte_addr = 9'd0;
    reg [7:0] sd_byte = 8'd0;

    reg bus_req = 1'b0;
    reg bus_we = 1'b0;
    reg [21:0] bus_addr = 22'd0;
    reg [1:0] bus_ds = 2'b11;
    reg [15:0] bus_wdata = 16'd0;
    wire bus_ready;
    wire bus_data_valid;
    wire [15:0] bus_data;
    wire bus_write_done;
    wire [9:0] audio;
    wire loading;
    wire loaded;
    wire failed;
    reg audio_seen = 1'b0;

    ql_qsound_card dut (
        .clk(clk), .reset(reset), .core_reset(core_reset),
        .ql_ce_10m5(1'b1),
        .image_mounted(image_mounted), .image_size(image_size),
        .sd_read_start(sd_read_start), .sd_sector(sd_sector),
        .sd_busy(sd_busy), .sd_done(sd_done),
        .sd_byte_valid(sd_byte_valid), .sd_byte_addr(sd_byte_addr),
        .sd_byte(sd_byte), .bus_req(bus_req), .bus_we(bus_we),
        .bus_addr(bus_addr), .bus_ds(bus_ds), .bus_wdata(bus_wdata),
        .bus_ready(bus_ready), .bus_data_valid(bus_data_valid),
        .bus_data(bus_data), .bus_write_done(bus_write_done),
        .audio(audio), .loading(loading), .loaded(loaded), .failed(failed)
    );

    always @(posedge clk)
        if (audio != 10'd0)
            audio_seen <= 1'b1;

    task automatic provide_sector;
        input integer sector_number;
        integer byte_number;
        integer absolute_byte;
        begin
            wait (sd_read_start);
            if (sd_sector != sector_number)
                $fatal(1, "QSound requested sector %0d, expected %0d",
                       sd_sector, sector_number);
            @(negedge clk);
            sd_busy = 1'b1;
            @(negedge clk);
            sd_busy = 1'b0;
            for (byte_number = 0; byte_number < 512;
                 byte_number = byte_number + 1) begin
                absolute_byte = sector_number * 512 + byte_number;
                sd_byte_addr = byte_number;
                sd_byte = absolute_byte == 0 ? 8'h4a :
                          absolute_byte == 1 ? 8'hfb :
                          absolute_byte[7:0];
                sd_byte_valid = 1'b1;
                @(negedge clk);
            end
            sd_byte_valid = 1'b0;
            sd_done = 1'b1;
            @(negedge clk);
            sd_done = 1'b0;
        end
    endtask

    task automatic bus_write_byte;
        input [23:0] address;
        input [7:0] value;
        begin
            @(negedge clk);
            bus_addr = address[22:1];
            bus_ds = address[0] ? 2'b10 : 2'b01;
            bus_wdata = {value, value};
            bus_we = 1'b1;
            bus_req = 1'b1;
            @(negedge clk);
            bus_req = 1'b0;
            bus_we = 1'b0;
            bus_ds = 2'b11;
            wait (bus_write_done);
            @(negedge clk);
        end
    endtask

    task automatic bus_read_word;
        input [23:0] address;
        input [15:0] expected;
        begin
            @(negedge clk);
            bus_addr = address[22:1];
            bus_ds = 2'b00;
            bus_we = 1'b0;
            bus_req = 1'b1;
            @(negedge clk);
            bus_req = 1'b0;
            wait (bus_data_valid);
            if (bus_data !== expected)
                $fatal(1, "QSound read %h at %h, expected %h",
                       bus_data, address, expected);
            @(negedge clk);
        end
    endtask

    task automatic ay_write;
        input [3:0] register_number;
        input [7:0] value;
        begin
            bus_write_byte(24'h0c2000, {4'd0, register_number});
            bus_write_byte(24'h0c2002, 8'h0f);
            bus_write_byte(24'h0c2002, 8'h0a);
            bus_write_byte(24'h0c2000, value);
            bus_write_byte(24'h0c2002, 8'h0e);
            bus_write_byte(24'h0c2002, 8'h0a);
        end
    endtask

    integer sector_number;
    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        image_size = 64'd8192;
        @(negedge clk);
        image_mounted = 1'b1;
        @(negedge clk);
        image_mounted = 1'b0;

        for (sector_number = 0; sector_number < 16;
             sector_number = sector_number + 1)
            provide_sector(sector_number);

        wait (loaded || failed);
        if (failed)
            $fatal(1, "Valid QSound ROM load failed");
        core_reset = 1'b0;
        bus_read_word(24'h0c0000, 16'h4afb);

        // Original ROM initialization sequence for the MC6821.
        bus_write_byte(24'h0c2001, 8'h00);
        bus_write_byte(24'h0c2000, 8'hff);
        bus_write_byte(24'h0c2001, 8'h04);
        bus_write_byte(24'h0c2003, 8'h00);
        bus_write_byte(24'h0c2002, 8'h0f);
        bus_write_byte(24'h0c2003, 8'h04);
        bus_write_byte(24'h0c2002, 8'h0a);

        ay_write(4'h0, 8'h01);
        ay_write(4'h1, 8'h00);
        ay_write(4'h7, 8'h3e);
        ay_write(4'h8, 8'h0f);
        repeat (6000) @(posedge clk);
        if (!audio_seen)
            $fatal(1, "AY-3-8910 tone did not reach the audio output");

        $display("PASS: QSound ROM, MC6821 interface, 0.75 MHz AY, and audio");
        $finish;
    end

endmodule
