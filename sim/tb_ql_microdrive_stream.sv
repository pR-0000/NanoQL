`timescale 1ns/1ps

module tb_ql_microdrive_stream;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg core_reset = 1'b1;
    always #5 clk = ~clk;
    reg [1:0] cpu_speed = 2'd0;
    reg selected = 1'b0;
    reg receive_ack = 1'b0;
    reg write_enable = 1'b0;
    reg erase_enable = 1'b0;
    reg tx_write = 1'b0;
    reg [7:0] tx_data = 8'd0;
    reg image_mounted = 1'b0;
    reg [63:0] image_size = 64'd0;
    wire sd_read_start;
    wire sd_write_start;
    wire [31:0] sd_sector;
    wire [7:0] sd_write_byte;
    reg sd_busy = 1'b0;
    reg sd_done = 1'b0;
    reg [2:0] sd_source = 3'd0;
    reg sd_byte_valid = 1'b0;
    reg [8:0] sd_byte_addr = 9'd0;
    reg [7:0] sd_byte = 8'd0;
    wire image_ready;
    wire gap;
    wire rx_ready;
    wire tx_full;
    wire [7:0] data;
    reg [7:0] written_sector [0:1535];

    ql_microdrive_stream #(
        .CLOCK_CYCLES_PER_BIT(16)
    ) dut (
        .clk(clk),
        .reset(reset),
        .core_reset(core_reset),
        .cpu_speed(cpu_speed),
        .selected(selected),
        .receive_ack(receive_ack),
        .write_enable(write_enable),
        .erase_enable(erase_enable),
        .tx_write(tx_write),
        .tx_data(tx_data),
        .image_mounted(image_mounted),
        .image_size(image_size),
        .sd_read_start(sd_read_start),
        .sd_write_start(sd_write_start),
        .sd_sector(sd_sector),
        .sd_write_byte(sd_write_byte),
        .sd_busy(sd_busy),
        .sd_done(sd_done),
        .sd_source(sd_source),
        .sd_byte_valid(sd_byte_valid),
        .sd_byte_addr(sd_byte_addr),
        .sd_byte(sd_byte),
        .image_ready(image_ready),
        .gap(gap),
        .tx_full(tx_full),
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
                sd_byte = (expected_sector == 0 &&
                           (index == 26 || index == 27)) ?
                          8'h00 : index[7:0] ^ xor_pattern;
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
            receive_ack = 1'b1;
            @(negedge clk);
            receive_ack = 1'b0;
            while (rx_ready)
                @(posedge clk);
        end
    endtask

    task automatic send_tx_byte;
        input [7:0] value;
        begin
            while (tx_full)
                @(posedge clk);
            @(negedge clk);
            tx_data = value;
            tx_write = 1'b1;
            @(negedge clk);
            tx_write = 1'b0;
            while (!tx_full)
                @(posedge clk);
            while (tx_full)
                @(posedge clk);
        end
    endtask

    task automatic service_writeback_read;
        input [31:0] expected_sector;
        input [7:0] xor_pattern;
        integer index;
        integer timeout;
        begin
            timeout = 0;
            while ((!sd_read_start || sd_sector != expected_sector) &&
                   timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 10000)
                $fatal(1,
                       "No writeback read for sector %0d (state=%0d, start=%0d, sector=%0d)",
                       expected_sector, dut.writeback_state,
                       sd_read_start, sd_sector);
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

    task automatic service_writeback_write;
        input [31:0] expected_sector;
        input integer output_base;
        integer index;
        integer timeout;
        begin
            timeout = 0;
            while ((!sd_write_start || sd_sector != expected_sector) &&
                   timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 10000)
                $fatal(1, "No canonical write for sector %0d", expected_sector);
            @(negedge clk);
            sd_source = 3'd2;
            sd_busy = 1'b1;
            @(negedge clk);
            sd_busy = 1'b0;
            for (index = 0; index < 512; index = index + 1) begin
                sd_byte_addr = index[8:0];
                @(negedge clk);
                written_sector[output_base + index] = sd_write_byte;
            end
            sd_done = 1'b1;
            @(negedge clk);
            sd_done = 1'b0;
            sd_source = 3'd0;
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
        core_reset = 1'b0;

        provide_sector(32'd0, 8'h00);
        provide_sector(32'd1, 8'h80);

        repeat (4) @(posedge clk);
        if (!image_ready)
            $fatal(1, "Microdrive image was not marked ready");

        // Emulator-oriented images can leave the derivable physical tail
        // zeroed. The hardware stream must regenerate its canonical words.
        @(negedge clk);
        dut.qlay_record_position = 10'd566;
        dut.stream_word = 16'h0000;
        #1;
        if (dut.normalized_stream_word !== 16'haa55)
            $fatal(1, "Microdrive calibration tail was not normalized");
        dut.qlay_record_position = 10'd650;
        #1;
        if (dut.normalized_stream_word !== 16'h193b)
            $fatal(1, "Microdrive tail checksum was not normalized");
        dut.qlay_record_position = 10'd652;
        #1;
        if (dut.normalized_stream_word !== 16'h5a5a)
            $fatal(1, "Microdrive padding was not normalized");
        dut.qlay_record_position = 10'd0;

        // The streamed cartridge must not consume the shared SD path while
        // the startup ROM is still loading and QDOS has not selected MDV1.
        repeat (400) @(posedge clk);
        if (dut.stream_started || dut.byte_position != 0)
            $fatal(1, "Microdrive started before its first QDOS selection");

        selected = 1'b1;
        // Switching from the authentic divider to 24 MHz while an old count
        // is already above the new terminal value must advance immediately,
        // not wait for an 8-bit wraparound.
        @(negedge clk);
        dut.phase_divider = 4'hf;
        cpu_speed = 2'd2;
        @(posedge clk);
        #1;
        if (dut.phase_divider !== 0)
            $fatal(1, "Live Microdrive acceleration did not resynchronize");
        @(negedge clk);
        cpu_speed = 2'd0;
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
        // Q-emuLator accepts QLAY images whose map-sector header checksum is
        // zero. NanoQL repairs that one missing checksum while streaming.
        expect_ready_byte(8'h12, 1'b1);
        expect_ready_byte(8'h10, 1'b1);

        // QDOS toggles drive selection while scanning. The cartridge must
        // continue moving instead of restarting from byte zero.
        selected = 1'b0;
        repeat (400) @(posedge clk);
        selected = 1'b1;
        expect_ready_byte(8'h28, 1'b0);

        // QDOS does not write bytes at their QLAY file offsets. It erases a
        // variable gap, emits 00..00 FF FF, then sends a decoded 612-byte
        // record. Start in record zero and deliberately stop after byte 529;
        // the immutable calibration tail must be regenerated.
        while (dut.bit_counter != 4'd0 || dut.phase_divider != 0)
            @(posedge clk);
        @(negedge clk);
        dut.byte_position = 18'd30;
        dut.qlay_record_position = 10'd30;
        dut.qlay_record_index = 8'd0;
        dut.buffer_valid = 2'b11;
        dut.buffer_sector[0] = 9'd0;
        dut.buffer_sector[1] = 9'd1;
        write_enable = 1'b1;
        erase_enable = 1'b1;
        repeat (2) @(posedge clk);
        begin : transmit_record
            integer index;
            for (index = 0; index < 7; index = index + 1)
                send_tx_byte(8'h00);
            send_tx_byte(8'hff);
            send_tx_byte(8'hff);
            for (index = 0; index < 530; index = index + 1)
                send_tx_byte(index[7:0] ^ 8'ha5);
        end

        @(negedge clk);
        write_enable = 1'b0;
        erase_enable = 1'b0;
        core_reset = 1'b1;
        service_writeback_read(32'd0, 8'h00);
        service_writeback_write(32'd0, 0);
        service_writeback_read(32'd1, 8'h80);
        service_writeback_write(32'd1, 512);
        @(negedge clk);
        core_reset = 1'b0;
        repeat (4) @(posedge clk);
        if (dut.byte_position != 0 || dut.stream_restart_pending)
            $fatal(1, "Reset interrupted or failed to rewind writeback");

        begin : verify_canonical_record
            integer index;
            reg [7:0] expected;
            for (index = 0; index < 1024; index = index + 1) begin
                expected = index < 512 ? index[7:0] :
                           (index - 512) ^ 8'h80;
                if (index >= 40 && index < 652) begin
                    if (index - 40 < 530)
                        expected = (index - 40) ^ 8'ha5;
                    else if (index - 40 < 610)
                        expected = (index - 40) & 1 ? 8'h55 : 8'haa;
                    else if (index - 40 == 610)
                        expected = 8'h19;
                    else
                        expected = 8'h3b;
                end
                if (written_sector[index] !== expected)
                    $fatal(1, "Canonical byte %0d is %02x, expected %02x",
                           index, written_sector[index], expected);
            end
        end

        // Record 11 begins at byte 418 of file sector 14 and therefore spans
        // three sectors. Exercise that less common alignment as well.
        begin : prepare_three_sector_record
            integer index;
            while (dut.writeback_state != dut.WB_IDLE)
                @(posedge clk);
            @(negedge clk);
            for (index = 0; index < 612; index = index + 1)
                dut.record_ram[index] = index[7:0] ^ 8'h3c;
            dut.capture_record_index = 8'd11;
            dut.capture_count = 10'd612;
            dut.capture_active = 1'b1;
            dut.previous_write_active = 1'b1;
            dut.sd_read_start = 1'b0;
            dut.read_in_flight = 1'b0;
            @(posedge clk);
            @(negedge clk);
            dut.previous_write_active = 1'b0;
        end
        service_writeback_read(32'd14, 8'h14);
        service_writeback_write(32'd14, 0);
        service_writeback_read(32'd15, 8'h15);
        service_writeback_write(32'd15, 512);
        service_writeback_read(32'd16, 8'h16);
        service_writeback_write(32'd16, 1024);
        begin : verify_three_sector_record
            integer index;
            reg [7:0] expected;
            for (index = 0; index < 1536; index = index + 1) begin
                if (index < 512)
                    expected = index[7:0] ^ 8'h14;
                else if (index < 1024)
                    expected = (index - 512) ^ 8'h15;
                else
                    expected = (index - 1024) ^ 8'h16;
                if (index >= 418 && index < 1030)
                    expected = (index - 418) ^ 8'h3c;
                if (written_sector[index] !== expected)
                    $fatal(1,
                           "Three-sector canonical byte %0d is %02x, expected %02x",
                           index, written_sector[index], expected);
            end
        end

        // QL RESET must rewind the logical tape after any pending writeback,
        // without unmounting the image or depending on CPU speed.
        while (dut.writeback_state != dut.WB_IDLE)
            @(posedge clk);
        @(negedge clk);
        dut.sd_read_start = 1'b0;
        dut.sd_write_start = 1'b0;
        dut.read_in_flight = 1'b0;
        dut.write_in_flight = 1'b0;
        dut.byte_position = 18'd1234;
        dut.qlay_record_position = 10'd548;
        dut.qlay_record_index = 8'd1;
        dut.stream_started = 1'b1;
        core_reset = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        core_reset = 1'b0;
        repeat (4) @(posedge clk);
        if (dut.byte_position != 0 || dut.qlay_record_position != 0 ||
            dut.qlay_record_index != 0 || dut.stream_started ||
            dut.stream_restart_pending)
            $fatal(1, "QL reset did not restart the Microdrive transport");

        provide_sector(32'd0, 8'h00);

        $display("PASS: QLAY read, normalized writeback, and reset restart");
        $finish;
    end
endmodule
