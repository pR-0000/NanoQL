`timescale 1ns/1ps

module tb_ql_hdmi_audio;
    reg clk_pixel = 1'b0;
    reg reset = 1'b1;
    reg ql_audio = 1'b0;
    reg [9:0] qsound_audio = 10'd0;
    reg qsound_audio_toggle = 1'b0;
    wire clk_audio;
    wire [15:0] sample_left;
    wire [15:0] sample_right;
    integer pixel_cycles = 0;
    integer first_sample_cycle;
    integer second_sample_cycle;

    always #5 clk_pixel = ~clk_pixel;
    always @(posedge clk_pixel)
        pixel_cycles <= pixel_cycles + 1;

    ql_hdmi_audio #(
        .PIXEL_CLOCK(1_000_000),
        .AUDIO_RATE(10_000),
        .AMPLITUDE(16'sh3000)
    ) dut (
        .clk_pixel(clk_pixel),
        .reset(reset),
        .ql_audio(ql_audio),
        .qsound_audio(qsound_audio),
        .qsound_audio_toggle(qsound_audio_toggle),
        .clk_audio(clk_audio),
        .sample_left(sample_left),
        .sample_right(sample_right)
    );

    initial begin
        repeat (3) @(posedge clk_pixel);
        if (sample_left !== 16'h0000 || sample_right !== 16'h0000)
            $fatal(1, "Audio must be muted during reset");

        reset = 1'b0;
        repeat (3) @(posedge clk_pixel);
        if (sample_left !== 16'hd000 || sample_right !== 16'hd000)
            $fatal(1, "Low QL audio level was not converted to negative PCM");

        ql_audio = 1'b1;
        repeat (3) @(posedge clk_pixel);
        if (sample_left !== 16'h3000 || sample_right !== 16'h3000)
            $fatal(1, "High QL audio level was not converted to positive PCM");

        ql_audio = 1'b0;
        repeat (3) @(posedge clk_pixel);
        if (sample_left !== 16'hd000)
            $fatal(1, "Low QL audio level changed unexpectedly");
        qsound_audio = 10'd512;
        repeat (5) @(posedge clk_pixel);
        if (sample_left !== 16'hd000)
            $fatal(1, "QSound changed before its atomic transfer marker");
        qsound_audio_toggle = 1'b1;
        repeat (7) @(posedge clk_pixel);
        if (sample_left !== 16'he000)
            $fatal(1, "Atomic QSound sample did not reach HDMI audio");

        @(posedge clk_audio);
        first_sample_cycle = pixel_cycles;
        @(posedge clk_audio);
        second_sample_cycle = pixel_cycles;
        if (second_sample_cycle - first_sample_cycle != 100)
            $fatal(1, "Audio sample period is %0d pixel clocks, expected 100",
                   second_sample_cycle - first_sample_cycle);

        $display("PASS: QL audio PCM conversion and sample clock");
        $finish;
    end
endmodule
