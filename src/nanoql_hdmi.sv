module nanoql_hdmi #(
    parameter PIXEL_CLOCK = 32_000_000
)(
    input  wire       clk_pixel_x5,
    input  wire       clk_pixel,
    input  wire       reset,
    input  wire       video_60hz,
    input  wire [23:0] rgb,
    input  wire       ql_audio,
    input  wire [9:0] qsound_audio,
    input  wire       qsound_audio_toggle,

    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);

    wire clk_audio;
    wire [15:0] audio_left;
    wire [15:0] audio_right;
    wire [15:0] audio_sample_word [1:0];
    assign audio_sample_word[0] = audio_left;
    assign audio_sample_word[1] = audio_right;

    ql_hdmi_audio #(
        .PIXEL_CLOCK(PIXEL_CLOCK),
        .AUDIO_RATE(48_000)
    ) audio_encoder (
        .clk_pixel(clk_pixel),
        .reset(reset),
        .ql_audio(ql_audio),
        .qsound_audio(qsound_audio),
        .qsound_audio_toggle(qsound_audio_toggle),
        .clk_audio(clk_audio),
        .sample_left(audio_left),
        .sample_right(audio_right)
    );

    wire [2:0] tmds;
    wire tmds_clock;

    hdmi #(
        .PICTURE_ASPECT_RATIO(2'b10),
        .VIDEO_RATE(PIXEL_CLOCK),
        .AUDIO_RATE(48000),
        .AUDIO_BIT_WIDTH(16),
        .VENDOR_NAME({"NanoQL", 16'd0}),
        .PRODUCT_DESCRIPTION({"NanoQL Test", 40'd0})
    ) hdmi_core (
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .clk_audio(clk_audio),
        .reset(reset),
        .stmode(2'd3),
        .rate_60(video_60hz),
        .screen(2'd0),
        .screen_width_override(11'd1280),
        .rgb(rgb),
        .audio_sample_word(audio_sample_word),
        .tmds(tmds),
        .tmds_clock(tmds_clock)
    );

    ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

endmodule

