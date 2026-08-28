`timescale 1ns/1ps

module tb_ql_video_scanout;
    reg reset = 1'b1;
    reg clk_bus = 1'b0;
    reg clk_pixel = 1'b0;
    reg visible = 1'b0;
    reg ql_area = 1'b0;
    reg ql_fetch_start = 1'b0;
    reg [7:0] ql_fetch_y = 8'd0;
    reg [8:0] ql_x = 9'd0;
    reg [7:0] ql_y = 8'd0;
    reg mode8 = 1'b0;
    reg blank = 1'b0;
    reg [21:0] frame_base = 22'h3f0000;
    reg frame_buffer_select = 1'b0;
    reg flash_phase = 1'b0;
    reg rd_ready = 1'b1;
    reg din_valid = 1'b0;
    reg [15:0] din = 16'd0;

    wire [21:0] addr;
    wire rd;
    wire fetch_underflow;
    wire scanout_buffer_select;
    wire [23:0] rgb;

    always #5 clk_bus = ~clk_bus;
    always #7 clk_pixel = ~clk_pixel;

    ql_video_scanout dut (
        .reset(reset),
        .clk_bus(clk_bus),
        .clk_pixel(clk_pixel),
        .visible(visible),
        .ql_area(ql_area),
        .ql_fetch_start(ql_fetch_start),
        .ql_fetch_y(ql_fetch_y),
        .ql_x(ql_x),
        .ql_y(ql_y),
        .mode8(mode8),
        .blank(blank),
        .frame_base(frame_base),
        .frame_buffer_select(frame_buffer_select),
        .flash_phase(flash_phase),
        .addr(addr),
        .rd(rd),
        .rd_ready(rd_ready),
        .din_valid(din_valid),
        .din(din),
        .fetch_underflow(fetch_underflow),
        .scanout_buffer_select(scanout_buffer_select),
        .rgb(rgb)
    );

    task request_line;
        input [7:0] y;
        begin
            @(negedge clk_pixel);
            ql_fetch_y = y;
            ql_fetch_start = 1'b1;
            @(negedge clk_pixel);
            ql_fetch_start = 1'b0;
            repeat (75) @(posedge clk_bus);
        end
    endtask

    task expect_frame;
        input [21:0] expected_base;
        input expected_select;
        begin
            if ((dut.fetch_frame_base !== expected_base) ||
                (scanout_buffer_select !== expected_select)) begin
                $display("FAIL: frame=%h/%b, expected %h/%b",
                         dut.fetch_frame_base, scanout_buffer_select,
                         expected_base, expected_select);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_bus);
        reset = 1'b0;

        request_line(8'd0);
        expect_frame(22'h3f0000, 1'b0);

        // A native QL page flip during this HDMI frame must not affect later
        // line fetches from the same frame.
        frame_base = 22'h3f4000;
        frame_buffer_select = 1'b1;
        request_line(8'd1);
        expect_frame(22'h3f0000, 1'b0);
        request_line(8'd127);
        expect_frame(22'h3f0000, 1'b0);
        request_line(8'd255);
        expect_frame(22'h3f0000, 1'b0);

        // The next frame adopts page 1 atomically at source line zero.
        request_line(8'd0);
        expect_frame(22'h3f4000, 1'b1);

        frame_base = 22'h3f0000;
        frame_buffer_select = 1'b0;
        request_line(8'd42);
        expect_frame(22'h3f4000, 1'b1);
        request_line(8'd0);
        expect_frame(22'h3f0000, 1'b0);

        $display("PASS: HDMI frame page selection is tear-free");
        $finish;
    end
endmodule
