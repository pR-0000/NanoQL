`timescale 1ns/1ps

module tb_ql_microdrive_stream;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;
    reg selected = 1'b0;
    reg status_read_ack = 1'b0;
    reg image_mounted = 1'b0;
    reg [63:0] image_size = 64'd0;
    wire sd_read_start;
    wire [31:0] sd_sector;
    reg sd_busy = 1'b0;
    reg sd_done = 1'b0;
    reg [2:0] sd_source = 3'd0;
    reg sd_byte_valid = 1'b0;
    reg [8:0] sd_byte_addr = 9'd0;
    reg [7:0] sd_byte = 8'd0;
    wire image_ready;
    wire gap;
    wire rx_ready;
    wire [7:0] data;

    ql_microdrive_stream #(
        .CLOCK_CYCLES_PER_BIT(16)
    ) dut (
        .clk(clk),
        .reset(reset),
        .selected(selected),
        .status_read_ack(status_read_ack),
        .image_mounted(image_mounted),
        .image_size(image_size),
        .sd_read_start(sd_read_start),
        .sd_sector(sd_sector),
        .sd_busy(sd_busy),
        .sd_done(sd_done),
        .sd_source(sd_source),
        .sd_byte_valid(sd_byte_valid),
        .sd_byte_addr(sd_byte_addr),
        .sd_byte(sd_byte),
        .image_ready(image_ready),
        .gap(gap),
        .tx_empty(),
        .rx_ready(rx_ready),
        .data(data),
        .debug_header_phase(),
        .debug_data_phase()
    );

    task automatic provide_sector;
        input [31:0] expected_sector;
        input [7:0] xor_pattern;
        integer index;
        integer timeout;
        begin
            timeout = 0;
            while ((!sd_read_start || sd_sector != expected_sector) &&
                   timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 2000)
                $fatal(1, "Microdrive did not request sector %0d",
                       expected_sector);

            @(negedge clk);
            sd_source = 3'd2;
            sd_busy = 1'b1;
            @(negedge clk);
            sd_busy = 1'b0;

            for (index = 0; index < 512; index = index + 1) begin
                sd_byte_addr = index[8:0];
                sd_byte = index[7:0] ^ xor_pattern;
                sd_byte_valid = 1'b1;
                @(negedge clk);
            end
            sd_byte_valid = 1'b0;
            sd_done = 1'b1;
            @(negedge clk);
            sd_done = 1'b0;
            sd_source = 3'd0;
        end
    endtask

    task automatic expect_ready_byte;
        input [7:0] expected;
        input expected_gap;
        integer timeout;
        begin
            timeout = 0;
            while (!rx_ready && timeout < 30000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 30000)
                $fatal(1, "Timed out waiting for Microdrive byte %02x",
                       expected);
            if (gap !== expected_gap)
                $fatal(1, "Microdrive GAP mismatch for byte %02x", expected);
            if (data !== expected)
                $fatal(1, "Microdrive returned %02x instead of %02x",
                       data, expected);
            repeat (8) begin
                @(posedge clk);
                if (!rx_ready || data !== expected)
                    $fatal(1, "RX byte changed before the status read");
            end
            @(negedge clk);
            status_read_ack = 1'b1;
            @(negedge clk);
            status_read_ack = 1'b0;
            while (rx_ready)
                @(posedge clk);
        end
    endtask

    initial begin
        // Persisted OSD images can be restored before the FPGA startup reset
        // is released. The mount must survive the remaining reset cycles.
        repeat (2) @(posedge clk);
        @(negedge clk);
        image_size = 64'd174930;
        image_mounted = 1'b1;
        @(negedge clk);
        image_mounted = 1'b0;
        repeat (2) @(posedge clk);
        reset = 1'b0;

        provide_sector(32'd0, 8'h00);
        provide_sector(32'd1, 8'h80);

        repeat (4) @(posedge clk);
        if (!image_ready)
            $fatal(1, "Microdrive image was not marked ready");

        // The streamed cartridge must not consume the shared SD path while
        // the startup ROM is still loading and QDOS has not selected MDV1.
        repeat (400) @(posedge clk);
        if (dut.stream_started || dut.byte_position != 0)
            $fatal(1, "Microdrive started before its first QDOS selection");

        selected = 1'b1;
        // The first six words are the physical preamble. RX ready starts on
        // the first header byte, matching the QL/MiSTer Microdrive path.
        expect_ready_byte(8'h0c, 1'b0);
        expect_ready_byte(8'h0d, 1'b0);
        expect_ready_byte(8'h0e, 1'b0);
        expect_ready_byte(8'h0f, 1'b0);
        expect_ready_byte(8'h10, 1'b0);
        expect_ready_byte(8'h11, 1'b0);
        expect_ready_byte(8'h12, 1'b0);
        expect_ready_byte(8'h13, 1'b0);
        expect_ready_byte(8'h14, 1'b0);
        expect_ready_byte(8'h15, 1'b0);
        expect_ready_byte(8'h16, 1'b0);
        expect_ready_byte(8'h17, 1'b0);
        expect_ready_byte(8'h18, 1'b0);
        expect_ready_byte(8'h19, 1'b0);
        // GAP rises when the checksum word enters the receive shifter. The
        // original ZX8302 still presents both checksum bytes to the CPU.
        expect_ready_byte(8'h1a, 1'b1);
        expect_ready_byte(8'h1b, 1'b1);

        // QDOS toggles drive selection while scanning. The cartridge must
        // continue moving instead of restarting from byte zero.
        selected = 1'b0;
        repeat (400) @(posedge clk);
        selected = 1'b1;
        expect_ready_byte(8'h28, 1'b0);

        $display("PASS: streaming QLAY Microdrive image and ZX8302 bytes");
        $finish;
    end
endmodule
