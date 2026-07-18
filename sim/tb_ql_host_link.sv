`timescale 1ns/1ps

module tb_ql_host_link;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg data_strobe = 1'b0;
    reg data_start = 1'b0;
    reg [7:0] data_in = 8'd0;
    wire [7:0] data_out;
    wire mem_req;
    wire mem_we;
    wire [21:0] mem_addr;
    wire [1:0] mem_ds;
    wire [15:0] mem_wdata;
    reg mem_write_done = 1'b0;
    wire cpu_hold;
    wire boot_vectors_active;
    wire [31:0] boot_ssp;
    wire [31:0] boot_pc;
    wire restart_pulse;
    integer writes = 0;

    always #5 clk = !clk;

    ql_host_link dut (
        .clk(clk), .reset(reset), .data_strobe(data_strobe),
        .data_start(data_start), .data_in(data_in), .data_out(data_out),
        .sdram_ready(1'b1), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_ds(mem_ds), .mem_wdata(mem_wdata),
        .mem_ready(1'b1), .mem_write_done(mem_write_done),
        .mem_data_valid(1'b0), .mem_rdata(16'd0),
        .cpu_addr(24'd0), .cpu_as_n(1'b1), .cpu_rw(1'b1),
        .cpu_dtack_n(1'b1), .cpu_fc(3'd0),
        .keyboard_report_count(8'h5a),
        .qlsd_status_flags(8'ha5), .qlsd_last_lba(24'h123456),
        .qlsd_header(32'h514c5741), .qlsd_byte_count(16'd512),
        .qlsd_crc32(32'h9abeb599),
        .qlsd_sample(64'h0005514c2d534420),
        .mdv_status_flags(8'h5f), .mdv_byte_position(18'h12345),
        .mdv_current_sector(9'h123), .mdv_buffer_valid(2'b11),
        .mdv_buffer_sector_0(9'h101), .mdv_buffer_sector_1(9'h002),
        .mdv_bit_counter(4'ha), .mdv_rx_count(16'h3456),
        .mdv_rx_missed_count(16'h1234),
        .mdv_rx_xor(8'ha5), .mdv_rx_last(8'hbc),
        .mdv_cpu_read_count(16'h789a), .mdv_cpu_read_xor(8'h5a),
        .mdv_cpu_read_last(8'hde),
        .mdv_cpu_trace_count(5'd16),
        .mdv_cpu_trace(128'h00112233445566778899aabbccddeeff),
        .mdv_data_trace_count(10'd518),
        .mdv_data_trace(128'hfd000c10aa55aa55aa55aa55aa55aa55),
        .cpu_speed(2'd1), .cpu_phase_count(32'h12345678),
        .cpu_hold(cpu_hold), .boot_vectors_active(boot_vectors_active),
        .boot_ssp(boot_ssp), .boot_pc(boot_pc),
        .restart_pulse(restart_pulse)
    );

    always @(posedge clk) begin
        mem_write_done <= mem_req;
        if (mem_req) begin
            case (writes)
                0: if (mem_addr != 22'h018000 || mem_ds != 2'b01 ||
                       mem_wdata != 16'h1200) $fatal(1, "write 0 mismatch");
                1: if (mem_addr != 22'h018000 || mem_ds != 2'b10 ||
                       mem_wdata != 16'h0034) $fatal(1, "write 1 mismatch");
                2: if (mem_addr != 22'h018001 || mem_ds != 2'b01 ||
                       mem_wdata != 16'h5600) $fatal(1, "write 2 mismatch");
                default: $fatal(1, "unexpected write");
            endcase
            writes <= writes + 1;
        end
    end

    task send_byte(input [7:0] value, input start);
        begin
            @(negedge clk);
            data_in = value;
            data_start = start;
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            data_start = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;

        send_byte(8'h00, 1'b1);
        if (data_out != 8'h4e) $fatal(1, "status signature N mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h51) $fatal(1, "status signature Q mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h4c) $fatal(1, "status signature L mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h31) $fatal(1, "status version mismatch");
        send_byte(8'h00, 1'b0);
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h5a) $fatal(1, "keyboard counter mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'ha5) $fatal(1, "QL-SD flags mismatch");
        send_byte(8'h00, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h51) $fatal(1, "QL-SD header byte 0 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h4c) $fatal(1, "QL-SD header byte 1 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h57) $fatal(1, "QL-SD header byte 2 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h41) $fatal(1, "QL-SD header byte 3 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h02) $fatal(1, "QL-SD byte count high mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h00) $fatal(1, "QL-SD byte count low mismatch");

        send_byte(8'h08, 1'b1);
        if (data_out != 8'h51) $fatal(1, "QL-SD detail Q mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h53) $fatal(1, "QL-SD detail S mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h44) $fatal(1, "QL-SD detail D mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h31) $fatal(1, "QL-SD detail version mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h9a) $fatal(1, "QL-SD CRC byte 0 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'hbe) $fatal(1, "QL-SD CRC byte 1 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'hb5) $fatal(1, "QL-SD CRC byte 2 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h99) $fatal(1, "QL-SD CRC byte 3 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h00) $fatal(1, "QL-SD sample byte 0 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h05) $fatal(1, "QL-SD sample byte 1 mismatch");

        send_byte(8'h09, 1'b1);
        if (data_out != 8'h43) $fatal(1, "CPU detail C mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h50) $fatal(1, "CPU detail P mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h55) $fatal(1, "CPU detail U mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h31) $fatal(1, "CPU detail version mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h01) $fatal(1, "CPU speed mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h12) $fatal(1, "CPU phase byte 0 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h34) $fatal(1, "CPU phase byte 1 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h56) $fatal(1, "CPU phase byte 2 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h78) $fatal(1, "CPU phase byte 3 mismatch");

        send_byte(8'h0a, 1'b1);
        if (data_out != 8'h4d) $fatal(1, "Microdrive detail M mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h44) $fatal(1, "Microdrive detail D mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h56) $fatal(1, "Microdrive detail V mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h33) $fatal(1, "Microdrive detail version mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h5f) $fatal(1, "Microdrive flags mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h01) $fatal(1, "Microdrive position high mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h23) $fatal(1, "Microdrive position middle mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h45) $fatal(1, "Microdrive position low mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h34) $fatal(1, "Microdrive RX count high mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h56) $fatal(1, "Microdrive RX count low mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h78) $fatal(1, "Microdrive read count high mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h9a) $fatal(1, "Microdrive read count low mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h12) $fatal(1, "Microdrive missed count high mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h34) $fatal(1, "Microdrive missed count low mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'hbc) $fatal(1, "Microdrive stream byte mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'hde) $fatal(1, "Microdrive read byte mismatch");

        send_byte(8'h0b, 1'b1);
        if (data_out != 8'h4d) $fatal(1, "Microdrive trace M mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h54) $fatal(1, "Microdrive trace T mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h10) $fatal(1, "Microdrive trace count mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h00) $fatal(1, "Microdrive trace byte 0 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h11) $fatal(1, "Microdrive trace byte 1 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h22) $fatal(1, "Microdrive trace byte 2 mismatch");

        send_byte(8'h0c, 1'b1);
        if (data_out != 8'h4d) $fatal(1, "Microdrive data trace M mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h42) $fatal(1, "Microdrive data trace B mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h02) $fatal(1, "Microdrive data count high mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h06) $fatal(1, "Microdrive data count low mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'hfd) $fatal(1, "Microdrive data byte 0 mismatch");
        send_byte(8'h00, 1'b0);
        if (data_out != 8'h00) $fatal(1, "Microdrive data byte 1 mismatch");

        send_byte(8'h01, 1'b1);
        if (!cpu_hold) $fatal(1, "HOLD did not stop the CPU");

        send_byte(8'h02, 1'b1);
        send_byte(8'h03, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'h03, 1'b0);
        send_byte(8'h12, 1'b0);
        send_byte(8'h34, 1'b0);
        send_byte(8'h56, 1'b0);
        wait (writes == 3);
        wait (!mem_write_done);

        send_byte(8'h03, 1'b1);
        send_byte(8'h00, 1'b0);
        send_byte(8'h03, 1'b0);
        send_byte(8'hff, 1'b0);
        send_byte(8'hf0, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'h03, 1'b0);
        send_byte(8'h00, 1'b0);
        send_byte(8'h00, 1'b0);
        @(posedge clk);
        if (cpu_hold || !boot_vectors_active ||
            boot_ssp != 32'h0003fff0 || boot_pc != 32'h00030000)
            $fatal(1, "EXEC vectors mismatch");

        $display("PASS: NanoQL Link hold/write/execute");
        $finish;
    end
endmodule
