`timescale 1ns/1ps

module tb_ql_hdmi_window;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [10:0] x = 11'd0;
    reg [9:0] y = 10'd0;
    reg [2:0] video_mode = 3'd0;
    wire visible;
    wire ql_area;
    wire ql_fetch_start;
    wire [7:0] ql_fetch_y;
    wire [8:0] ql_x;
    wire [7:0] ql_y;

    always #5 clk = ~clk;

    ql_hdmi_window dut (
        .clk(clk), .reset(reset), .x(x), .y(y),
        .video_mode(video_mode), .visible(visible), .ql_area(ql_area),
        .ql_fetch_start(ql_fetch_start), .ql_fetch_y(ql_fetch_y),
        .ql_x(ql_x), .ql_y(ql_y)
    );

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_profile;
        input [2:0] mode;
        input [10:0] left;
        input [10:0] width;
        input [9:0] top;
        input [9:0] height;
        integer index;
        begin
            video_mode = 3'd7;
            reset = 1'b1;
            tick();
            reset = 1'b0;
            video_mode = mode;

            y = top;
            x = left;
            tick();
            if (ql_x != 9'd0 || ql_y != 8'd0)
                $fatal(1, "mode %0d did not start at source 0,0", mode);

            for (index = 1; index < width; index = index + 1) begin
                x = left + index;
                tick();
                if ((index == 1) && (ql_x == 9'd0) && (width == 11'd512))
                    $fatal(1, "mode %0d scaler did not advance at x=%0d, left=%0d width=%0d area=%0d phase=%0d sum=%0d",
                           mode, x, dut.ql_left, dut.ql_width, dut.in_ql_area,
                           dut.horizontal_phase, dut.horizontal_sum);
            end
            if (ql_x != 9'd511)
                $fatal(1, "mode %0d ended at source x=%0d", mode, ql_x);

            x = 11'd0;
            for (index = 1; index < height; index = index + 1) begin
                y = top + index;
                tick();
            end
            if (ql_y != 8'd255)
                $fatal(1, "mode %0d ended at source y=%0d", mode, ql_y);
        end
    endtask

    initial begin
        check_profile(3'd0, 11'd358, 11'd564, 10'd168, 10'd384);
        check_profile(3'd1, 11'd218, 11'd844, 10'd72, 10'd576);
        check_profile(3'd2, 11'd145, 11'd990, 10'd22, 10'd675);
        check_profile(3'd3, 11'd358, 11'd564, 10'd168, 10'd384);
        check_profile(3'd4, 11'd218, 11'd844, 10'd72, 10'd576);
        check_profile(3'd5, 11'd145, 11'd990, 10'd22, 10'd675);
        $display("PASS: all 720p50/60 QL windows cover 512x256 at 4.4:3");
        $finish;
    end
endmodule
