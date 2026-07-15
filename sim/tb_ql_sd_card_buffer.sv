`timescale 1ns/1ps

module tb_ql_sd_card_buffer;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg img_mounted = 1'b0;
    reg sd_ack = 1'b0;
    reg [8:0] sd_buff_addr = 9'd0;
    reg [7:0] sd_buff_dout = 8'd0;
    reg sd_buff_wr = 1'b0;
    wire [7:0] sd_buff_din;
    integer i;

    always #5 clk = ~clk;

    ql_sd_card dut (
        .clk_sys(clk),
        .reset(reset),
        .sdhc(1'b1),
        .img_mounted(img_mounted),
        .img_size(64'd41943040),
        .sd_lba(),
        .sd_rd(),
        .sd_wr(),
        .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr),
        .sd_buff_dout(sd_buff_dout),
        .sd_buff_din(sd_buff_din),
        .sd_buff_wr(sd_buff_wr),
        .clk_spi(clk),
        .ss(1'b1),
        .sck(1'b1),
        .mosi(1'b1),
        .miso()
    );

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        img_mounted = 1'b1;
        @(posedge clk);
        img_mounted = 1'b0;

        // The physical SD controller supplies all bytes before sd_ack.
        // Verify that this ordering still fills the virtual-card buffer.
        for (i = 0; i < 512; i = i + 1) begin
            @(negedge clk);
            sd_buff_addr = i[8:0];
            sd_buff_dout = (i == 0) ? 8'h51 :
                           (i == 1) ? 8'h4c :
                           (i == 2) ? 8'h57 :
                           (i == 3) ? 8'h41 : i[7:0];
            sd_buff_wr = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        sd_buff_wr = 1'b0;

        if (dut.sector_ram[0] !== 8'h51 ||
            dut.sector_ram[1] !== 8'h4c ||
            dut.sector_ram[2] !== 8'h57 ||
            dut.sector_ram[3] !== 8'h41 ||
            dut.sector_ram[511] !== 8'hff)
            $fatal(1, "sector bytes were not captured before sd_ack");

        sd_ack = 1'b1;
        repeat (5) @(posedge clk);
        sd_ack = 1'b0;
        repeat (5) @(posedge clk);
        if (dut.sd_buf !== 2'd1)
            $fatal(1, "sector ring did not advance after sd_ack");

        $display("PASS: QL-SD physical bridge fills a complete sector before ack");
        $finish;
    end
endmodule
