`timescale 1ns/1ps

module tb_ql_sd_qlromext;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg romoel = 1'b1;
    reg [15:0] address = 16'd0;
    wire [7:0] data_out;
    wire dtack;
    wire sd_clk;
    wire sd_cs1_n;
    wire sd_cs2_n;
    wire sd_mosi;

    always #5 clk = ~clk;

    ql_sd_qlromext #(.DTACK_DELAY(3), .SLOW_DIVIDER(2)) dut (
        .clk(clk), .reset(reset), .ce_sd(1'b1), .romoel(romoel),
        .address(address), .data_out(data_out), .dtack(dtack),
        .sd_clk(sd_clk), .sd_cs1_n(sd_cs1_n), .sd_cs2_n(sd_cs2_n),
        .sd_mosi(sd_mosi), .sd_miso(1'b1)
    );

    task automatic ql_read;
        input [15:0] read_address;
        begin
            @(negedge clk);
            address = read_address;
            romoel = 1'b0;
            wait (dtack);
            @(negedge clk);
            romoel = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        ql_read(16'hfee0);
        ql_read(16'hfef1);
        if (sd_cs1_n !== 1'b0 || sd_cs2_n !== 1'b1)
            $fatal(1, "QL-SD card 1 selection failed");

        ql_read(16'hfee6);
        ql_read(16'hffa5);
        wait (!dut.transfer_running && dut.spi_state == 3'd0);
        if (dut.shift_reg !== 8'hff)
            $fatal(1, "background SPI did not shift MISO into the register");
        ql_read(16'hfee4);
        if (data_out !== 8'hff)
            $fatal(1, "SPI read register returned %h", data_out);

        ql_read(16'hfef0);
        if (sd_cs1_n !== 1'b1 || sd_cs2_n !== 1'b1)
            $fatal(1, "QL-SD deselection failed");
        $display("PASS: QLROMEXT register and background SPI behavior");
        $finish;
    end
endmodule
