`timescale 1ns/1ps

module tb_ql_cpu_address;
    reg [23:1] word_addr;
    reg uds_n;
    reg lds_n;
    reg [1:0] ram_config;
    wire [23:0] byte_addr;

    ql_cpu_address dut (
        .word_addr(word_addr),
        .uds_n(uds_n),
        .lds_n(lds_n),
        .ram_config(ram_config),
        .byte_addr(byte_addr)
    );

    task automatic expect_addr;
        input [23:0] source_addr;
        input source_uds_n;
        input source_lds_n;
        input [1:0] source_ram_config;
        input [23:0] expected_addr;
        begin
            word_addr = source_addr[23:1];
            uds_n = source_uds_n;
            lds_n = source_lds_n;
            ram_config = source_ram_config;
            #1;
            if (byte_addr !== expected_addr)
                $fatal(1, "address %h decoded as %h, expected %h",
                       source_addr, byte_addr, expected_addr);
        end
    endtask

    initial begin
        expect_addr(24'h020100, 1'b0, 1'b1, 2'd0, 24'h020100);
        expect_addr(24'h020100, 1'b1, 1'b0, 2'd0, 24'h020101);
        expect_addr(24'h060100, 1'b0, 1'b1, 2'd0, 24'h020100);
        expect_addr(24'hfe0100, 1'b1, 1'b0, 2'd0, 24'h020101);
        expect_addr(24'h040000, 1'b0, 1'b0, 2'd0, 24'h000000);
        expect_addr(24'h0e0100, 1'b0, 1'b1, 2'd1, 24'h0e0100);
        expect_addr(24'h1e0100, 1'b0, 1'b1, 2'd2, 24'h0e0100);
        expect_addr(24'h8e0100, 1'b0, 1'b1, 2'd3, 24'h0e0100);

        $display("PASS: QL address masks follow the selected RAM configuration");
        $finish;
    end
endmodule
