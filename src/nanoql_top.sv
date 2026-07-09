`define GOWIN

module nanoql_top(
    input  wire       clk_27m,
    output wire [5:0] leds_n,

    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);

    wire clk_pixel_x5;
    wire clk_pixel;
    wire pll_lock;

    pll_160m pll_hdmi (
        .clkout(clk_pixel_x5),
        .lock(pll_lock),
        .clkin(clk_27m)
    );

    Gowin_CLKDIV clk_div_5 (
        .hclkin(clk_pixel_x5),
        .resetn(pll_lock),
        .clkout(clk_pixel)
    );

    reg [15:0] reset_shift = 16'hffff;
    always @(posedge clk_pixel or negedge pll_lock) begin
        if (!pll_lock)
            reset_shift <= 16'hffff;
        else
            reset_shift <= {reset_shift[14:0], 1'b0};
    end

    wire video_reset = reset_shift[15];
    wire [23:0] rgb;
    wire frame_pulse;
    wire [10:0] x;
    wire [9:0] y;
    wire mode8_active;
    wire blank_active;

    ql_video_test ql_video_test (
        .clk_pixel(clk_pixel),
        .reset(video_reset),
        .rgb(rgb),
        .frame_pulse(frame_pulse),
        .mode8_active(mode8_active),
        .blank_active(blank_active),
        .x(x),
        .y(y)
    );


    wire ql_native_ce;
    wire ql_native_hs;
    wire ql_native_vs;
    wire ql_native_active;
    wire ql_native_vblank;
    wire ql_native_frame;
    wire [9:0] ql_native_h;
    wire [9:0] ql_native_v;

    ql_native_timing_probe ql_native_timing_probe (
        .clk_pixel(clk_pixel),
        .reset(video_reset),
        .ntsc(1'b0),
        .ce_ql(ql_native_ce),
        .h_cnt(ql_native_h),
        .v_cnt(ql_native_v),
        .hs(ql_native_hs),
        .vs(ql_native_vs),
        .active(ql_native_active),
        .vblank(ql_native_vblank),
        .frame_pulse(ql_native_frame)
    );

    reg [5:0] ql_native_frame_div = 6'd0;
    always @(posedge clk_pixel or posedge video_reset) begin
        if (video_reset)
            ql_native_frame_div <= 6'd0;
        else if (ql_native_frame)
            ql_native_frame_div <= ql_native_frame_div + 6'd1;
    end
    nanoql_hdmi #(
        .PIXEL_CLOCK(32_000_000)
    ) hdmi_out (
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .reset(video_reset),
        .rgb(rgb),
        .tmds_clk_n(tmds_clk_n),
        .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n),
        .tmds_d_p(tmds_d_p)
    );

    reg [24:0] heartbeat = 25'd0;
    always @(posedge clk_pixel or negedge pll_lock) begin
        if (!pll_lock)
            heartbeat <= 25'd0;
        else
            heartbeat <= heartbeat + 25'd1;
    end

    // Board LEDs are active-low on the Tang Nano 20K.
    assign leds_n[0] = ~heartbeat[24];
    assign leds_n[1] = ~pll_lock;
    assign leds_n[2] = ~frame_pulse;
    assign leds_n[3] = ~blank_active;
    assign leds_n[4] = ~mode8_active;
    assign leds_n[5] = ~ql_native_frame_div[5];

endmodule



