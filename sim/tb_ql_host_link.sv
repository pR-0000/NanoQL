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
