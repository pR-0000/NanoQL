`timescale 1ns/1ps

module tb_ql_sdram_router;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg host_req = 1'b0;
    reg host_we = 1'b0;
    reg [21:0] host_addr = 22'd0;
    reg [1:0] host_ds = 2'b00;
    reg [15:0] host_wdata = 16'd0;
    reg loader_req = 1'b0;
    reg loader_we = 1'b0;
    reg [21:0] loader_addr = 22'd0;
    reg [1:0] loader_ds = 2'b00;
    reg [15:0] loader_wdata = 16'd0;
    reg rom_req = 1'b0;
    reg [21:0] rom_addr = 22'd0;
    reg ram_req = 1'b0;
    reg ram_we = 1'b0;
    reg [21:0] ram_addr = 22'd0;
    reg [1:0] ram_ds = 2'b00;
    reg [15:0] ram_wdata = 16'd0;
    reg snapshot_req = 1'b0;
    reg snapshot_we = 1'b0;
    reg [21:0] snapshot_addr = 22'd0;
    reg [1:0] snapshot_ds = 2'b00;
    reg [15:0] snapshot_wdata = 16'd0;
    reg system_ready = 1'b1;
    reg system_data_valid = 1'b0;
    reg [15:0] system_data = 16'd0;
    reg system_write_done = 1'b0;

    wire host_ready;
    wire host_data_valid;
    wire [15:0] host_data;
    wire host_write_done;
    wire loader_ready;
    wire loader_data_valid;
    wire [15:0] loader_data;
    wire loader_write_done;
    wire rom_ready;
    wire rom_data_valid;
    wire [15:0] rom_data;
    wire ram_ready;
    wire ram_data_valid;
    wire [15:0] ram_data;
    wire ram_write_done;
    wire snapshot_ready;
    wire snapshot_data_valid;
    wire [15:0] snapshot_data;
    wire snapshot_write_done;
    wire system_req;
    wire system_we;
    wire [21:0] system_addr;
    wire [1:0] system_ds;
    wire [15:0] system_wdata;

    always #5 clk = ~clk;

    ql_sdram_router dut (
        .clk(clk), .reset(reset),
        .host_req(host_req), .host_we(host_we), .host_addr(host_addr),
        .host_ds(host_ds), .host_wdata(host_wdata),
        .host_ready(host_ready), .host_data_valid(host_data_valid),
        .host_data(host_data), .host_write_done(host_write_done),
        .loader_req(loader_req), .loader_we(loader_we),
        .loader_addr(loader_addr), .loader_ds(loader_ds),
        .loader_wdata(loader_wdata), .loader_ready(loader_ready),
        .loader_data_valid(loader_data_valid), .loader_data(loader_data),
        .loader_write_done(loader_write_done),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ready(rom_ready),
        .rom_data_valid(rom_data_valid), .rom_data(rom_data),
        .ram_req(ram_req), .ram_we(ram_we), .ram_addr(ram_addr),
        .ram_ds(ram_ds), .ram_wdata(ram_wdata), .ram_ready(ram_ready),
        .ram_data_valid(ram_data_valid), .ram_data(ram_data),
        .ram_write_done(ram_write_done),
        .snapshot_req(snapshot_req), .snapshot_we(snapshot_we),
        .snapshot_addr(snapshot_addr), .snapshot_ds(snapshot_ds),
        .snapshot_wdata(snapshot_wdata), .snapshot_ready(snapshot_ready),
        .snapshot_data_valid(snapshot_data_valid),
        .snapshot_data(snapshot_data),
        .snapshot_write_done(snapshot_write_done),
        .system_req(system_req), .system_we(system_we),
        .system_addr(system_addr), .system_ds(system_ds),
        .system_wdata(system_wdata), .system_ready(system_ready),
        .system_data_valid(system_data_valid), .system_data(system_data),
        .system_write_done(system_write_done)
    );

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        loader_req = 1'b1;
        loader_we = 1'b1;
        loader_addr = 22'h3f8123;
        loader_wdata = 16'h1234;
        ram_req = 1'b1;
        ram_addr = 22'h010000;
        #1;
        if (!system_req || !loader_ready || ram_ready || !system_we ||
            system_addr != loader_addr || system_wdata != 16'h1234)
            $fatal(1, "ROM loader did not win SDRAM arbitration");

        @(posedge clk);
        #1;
        loader_req = 1'b0;
        ram_req = 1'b0;
        system_ready = 1'b0;
        system_write_done = 1'b1;
        #1;
        if (!loader_write_done || host_write_done || ram_write_done)
            $fatal(1, "Loader write completion reached the wrong client");
        @(posedge clk);
        #1;
        system_write_done = 1'b0;

        @(posedge clk);
        #1;
        system_ready = 1'b1;
        rom_req = 1'b1;
        rom_addr = 22'h3f8002;
        #1;
        if (!system_req || !rom_ready || system_we || system_addr != rom_addr)
            $fatal(1, "CPU ROM read was not selected");

        @(posedge clk);
        #1;
        rom_req = 1'b0;
        system_ready = 1'b0;
        system_data = 16'hbeef;
        system_data_valid = 1'b1;
        #1;
        if (!rom_data_valid || rom_data != 16'hbeef ||
            host_data_valid || loader_data_valid || ram_data_valid)
            $fatal(1, "ROM data reached the wrong SDRAM client");
        @(posedge clk);
        #1;
        system_data_valid = 1'b0;

        @(posedge clk);
        #1;
        system_ready = 1'b1;
        host_req = 1'b1;
        host_addr = 22'h000010;
        ram_req = 1'b1;
        ram_addr = 22'h010010;
        #1;
        if (!host_ready || ram_ready || system_addr != host_addr)
            $fatal(1, "NanoQL Link did not receive highest priority");

        host_req = 1'b0;
        snapshot_req = 1'b1;
        snapshot_addr = 22'h3f0010;
        #1;
        if (!ram_ready || snapshot_ready || system_addr != ram_addr)
            $fatal(1, "QL RAM did not arbitrate ahead of HDMI snapshot");

        ram_req = 1'b0;
        #1;
        if (!snapshot_ready || system_addr != snapshot_addr)
            $fatal(1, "HDMI snapshot did not use the free SDRAM slot");

        $display("PASS: SDRAM routing priority and response ownership");
        $finish;
    end
endmodule
