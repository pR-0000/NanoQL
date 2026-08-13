`timescale 1ns/1ps

module tb_hdmi_video_modes;
    logic [7:0] cea = 8'd19;
    wire [23:0] header;
    wire [55:0] sub [3:0];

    auxiliary_video_information_info_frame #(
        .PICTURE_ASPECT_RATIO(2'b10)
    ) dut (
        .stmode(2'd3),
        .cea(cea),
        .header(header),
        .sub(sub)
    );

    task check_vic;
        input [7:0] expected_vic;
        begin
            cea = expected_vic;
            #1;
            if (header !== 24'h0d0282 || sub[0][39:32] !== expected_vic ||
                sub[0][23:16] !== 8'h29) begin
                $display("FAIL: malformed 16:9 AVI InfoFrame for VIC %0d", expected_vic);
                $fatal(1);
            end
        end
    endtask

    initial begin
        check_vic(8'd19);
        check_vic(8'd4);
        $display("PASS: HDMI AVI InfoFrame carries VIC 19/4 with 16:9 aspect");
        $finish;
    end
endmodule
