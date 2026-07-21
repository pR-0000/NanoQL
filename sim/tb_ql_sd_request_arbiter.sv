`timescale 1ns/1ps

module tb_ql_sd_request_arbiter;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    reg rom_read = 1'b0;
    reg qlsd_read = 1'b0;
    reg qlsd_write = 1'b0;
    reg mdv_read = 1'b0;
    reg mdv_write = 1'b0;
    reg qsound_read = 1'b0;
    reg busy = 1'b0;
    reg done = 1'b0;
    wire [7:0] rstart;
    wire [7:0] wstart;
    wire [31:0] sector;

    ql_sd_request_arbiter dut (
        .clk(clk), .reset(reset),
        .rom_read_start(rom_read), .rom_sector(32'h10),
        .qlsd_read_start(qlsd_read),
        .qlsd_write_start(qlsd_write), .qlsd_sector(32'h20),
        .mdv_read_start(mdv_read), .mdv_write_start(mdv_write),
        .mdv_sector(32'h30),
        .qsound_read_start(qsound_read), .qsound_sector(32'h40),
        .sd_busy(busy), .sd_done(done),
        .sd_read_start(rstart), .sd_write_start(wstart),
        .sd_sector(sector)
    );

    task automatic expect_read;
        input [7:0] expected_start;
        input [31:0] expected_sector;
        integer timeout;
        begin
            timeout = 0;
            while (rstart != expected_start && timeout < 20) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (rstart != expected_start || sector != expected_sector)
                $fatal(1, "Unexpected read arbitration: %02x/%08x",
                       rstart, sector);
            @(negedge clk); busy = 1'b1;
            @(negedge clk); busy = 1'b0;
            repeat (2) @(negedge clk);
            done = 1'b1;
            @(negedge clk); done = 1'b0;
        end
    endtask

    task automatic expect_write;
        input [7:0] expected_start;
        input [31:0] expected_sector;
        integer timeout;
        begin
            timeout = 0;
            while (wstart != expected_start && timeout < 20) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (wstart != expected_start || sector != expected_sector)
                $fatal(1, "Unexpected write arbitration: %02x/%08x",
                       wstart, sector);
            @(negedge clk); busy = 1'b1;
            @(negedge clk); busy = 1'b0;
            repeat (2) @(negedge clk);
            done = 1'b1;
            @(negedge clk); done = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;
        rom_read = 1'b1;
        qlsd_read = 1'b1;
        mdv_read = 1'b1;

        expect_read(8'h01, 32'h10);
        rom_read = 1'b0;
        expect_read(8'h02, 32'h20);
        qlsd_read = 1'b0;
        expect_read(8'h04, 32'h30);
        mdv_read = 1'b0;
        repeat (3) @(posedge clk);
        mdv_write = 1'b1;
        expect_write(8'h04, 32'h30);
        mdv_write = 1'b0;
        repeat (3) @(posedge clk);
        qsound_read = 1'b1;
        expect_read(8'h08, 32'h40);
        qsound_read = 1'b0;

        repeat (4) @(posedge clk);
        if (rstart != 0 || wstart != 0)
            $fatal(1, "Arbiter did not return idle");
        $display("PASS: serialized ROM, QL-SD, Microdrive, and QSound requests");
        $finish;
    end
endmodule
