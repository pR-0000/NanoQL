module ql_video_test(
    input  wire        clk_bus,
    input  wire        clk_pixel,
    input  wire        reset,
    input  wire        core_reset,
    input  wire [1:0]  aspect_mode,
    output wire [18:0] mem_addr,
    output wire        mem_rd,
    input  wire        mem_ready,
    input  wire        mem_data_valid,
    input  wire [15:0] mem_data,
    input  wire        mc_stat_wr,
    input  wire [7:0]  mc_stat_data,
    output wire [23:0] rgb,
    output wire        mode8_active,
    output wire        blank_active,
    output wire        ql_ce,
    output wire [9:0]  ql_h,
    output wire [9:0]  ql_v,
    output wire        ql_hs,
    output wire        ql_vs,
    output wire        ql_hblank,
    output wire        ql_vblank,
    output wire        ql_frame,
    output wire        fetch_underflow,
    output reg  [10:0] x,
    output reg  [9:0]  y
);

    // CEA-861 1280x720p50: 74.25 MHz, 1980x750 total pixels.
    localparam [10:0] FRAME_W = 11'd1980;
    localparam [9:0]  FRAME_H = 10'd750;

    wire visible_now;
    wire ql_area_now;
    wire ql_fetch_start_now;
    wire [7:0] ql_fetch_y_now;
    wire [8:0] ql_x_now;
    wire [7:0] ql_y_now;

    ql_hdmi_window hdmi_window (
        .clk(clk_pixel),
        .reset(reset),
        .x(x),
        .y(y),
        .aspect_mode(aspect_mode),
        .visible(visible_now),
        .ql_area(ql_area_now),
        .ql_fetch_start(ql_fetch_start_now),
        .ql_fetch_y(ql_fetch_y_now),
        .ql_x(ql_x_now),
        .ql_y(ql_y_now)
    );

    always @(posedge clk_pixel) begin
        if (reset) begin
            x <= 11'd0;
            y <= 10'd0;
        end else begin
            if (x == FRAME_W - 1'b1) begin
                x <= 11'd0;
                if (y == FRAME_H - 1'b1) begin
                    y <= 10'd0;
                end else begin
                    y <= y + 10'd1;
                end
            end else begin
                x <= x + 11'd1;
            end
        end
    end

    wire video_membase;
    wire video_ntsc;

    ql_zx8301 zx8301 (
        .reset(reset),
        .core_reset(core_reset),
        .clk_pixel(clk_pixel),
        .clk_bus(clk_bus),
        .cpu_cs(mc_stat_wr),
        .cpu_data(mc_stat_data),
        .visible(visible_now),
        .ql_area(ql_area_now),
        .ql_fetch_start(ql_fetch_start_now),
        .ql_fetch_y(ql_fetch_y_now),
        .ql_x(ql_x_now),
        .ql_y(ql_y_now),
        .addr(mem_addr),
        .rd(mem_rd),
        .rd_ready(mem_ready),
        .din_valid(mem_data_valid),
        .din(mem_data),
        .fetch_underflow(fetch_underflow),
        .mode8(mode8_active),
        .blank(blank_active),
        .membase(video_membase),
        .ntsc(video_ntsc),
        .native_ce(ql_ce),
        .native_h(ql_h),
        .native_v(ql_v),
        .native_hs(ql_hs),
        .native_vs(ql_vs),
        .native_hblank(ql_hblank),
        .native_vblank(ql_vblank),
        .native_frame(ql_frame),
        .rgb(rgb)
    );

endmodule
