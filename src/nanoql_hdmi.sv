module nanoql_hdmi #(
    parameter PIXEL_CLOCK = 32_000_000
)(
    input  wire       clk_pixel_x5,
    input  wire       clk_pixel,
    input  wire       reset,
    input  wire [23:0] rgb,

    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);

    reg clk_audio = 1'b0;
    // NanoQL currently emits DVI-compatible video without audio packets.
    // Keeping this counter intentionally below the 720p audio divider lets
    // synthesis remove the unused auxiliary packet path.
    reg [8:0] aclk_cnt = 9'd0;

    always @(posedge clk_pixel) begin
        if (aclk_cnt < PIXEL_CLOCK / 48000 / 2 - 1)
            aclk_cnt <= aclk_cnt + 9'd1;
        else begin
            aclk_cnt <= 9'd0;
            clk_audio <= ~clk_audio;
        end
    end

    wire [15:0] audio_sample_word [1:0];
    assign audio_sample_word[0] = 16'd0;
    assign audio_sample_word[1] = 16'd0;

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

