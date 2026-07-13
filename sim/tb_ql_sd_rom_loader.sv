`timescale 1ns/1ps

module tb_ql_sd_rom_loader;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b0;
    reg image_mounted = 1'b0;
    reg [63:0] image_size = 64'd0;
    wire sd_read_start;
    wire [31:0] sd_sector;
    wire mem_req;
    wire mem_we;
    wire [21:0] mem_addr;
    wire [1:0] mem_ds;
    wire [15:0] mem_wdata;
    wire loading;
    wire loaded;
    wire failed;
    wire [7:0] sector_progress;

    always #5 clk = ~clk;

    ql_sd_rom_loader dut (
        .clk(clk), .reset(reset), .enable(enable),
        .image_mounted(image_mounted), .image_size(image_size),
        .sd_read_start(sd_read_start), .sd_sector(sd_sector),
        .sd_busy(1'b0), .sd_done(1'b0),
        .sd_byte_valid(1'b0), .sd_byte_addr(9'd0), .sd_byte(8'd0),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_ds(mem_ds), .mem_wdata(mem_wdata), .mem_ready(1'b1),
        .mem_data_valid(1'b0), .mem_data(16'd0),
        .mem_write_done(1'b0), .loading(loading), .loaded(loaded),
        .failed(failed), .sector_progress(sector_progress)
    );

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;

        // Reproduce the hardware race: the Companion announces QL.rom while
        // SDRAM initialization still keeps the loader disabled.
        @(posedge clk);
        image_size <= 64'd49152;
        image_mounted <= 1'b1;
        @(posedge clk);
        image_mounted <= 1'b0;
        repeat (20) @(posedge clk);

        if (loading || sd_read_start)
            $fatal(1, "loader started while disabled");

        enable <= 1'b1;
        repeat (5) @(posedge clk);

        if (!loading || !sd_read_start || failed)
            $fatal(1, "mount event emitted during SDRAM init was lost");

        $display("PASS: delayed ROM loader consumes an early mount event");
        $finish;
    end
endmodule
