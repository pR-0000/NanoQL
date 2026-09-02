module ql_video_test(
    input  wire        clk_bus,
    input  wire        clk_pixel,
    input  wire        reset,
    input  wire        core_reset,
    input  wire [2:0]  video_mode,
    input  wire        snapshot_valid,
    input  wire [21:0] snapshot_base,
    input  wire        snapshot_buffer_select,
    output wire        scanout_buffer_select,
    output wire        membase_active,
    output wire [21:0] mem_addr,
    output wire        mem_rd,
    input  wire        mem_ready,
    input  wire        mem_data_valid,
    input  wire [15:0] mem_data,
    input  wire        mc_stat_wr,
    input  wire [7:0]  mc_stat_data,
    output wire [23:0] rgb,
    output wire        mode8_active,
    output wire        blank_active,
    output wire        flash_phase_active,
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

    // Both rates share the 74.25 MHz pixel clock. The PAL-compatible raster
    // uses 1977 clocks per line so its frame cadence closely tracks the
    // native 50.080 Hz QL raster; the 60 Hz compatibility mode remains VIC 4.
    wire video_60hz = video_mode >= 3'd3;
    wire [10:0] frame_w = video_60hz ? 11'd1650 : 11'd1977;
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
        .video_mode(video_mode),
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
            if (x >= frame_w - 1'b1) begin
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
    wire [21:0] live_frame_base = video_membase ?
                                        22'h014000 : 22'h010000;
    wire [21:0] selected_frame_base = snapshot_valid ?
                                            snapshot_base : live_frame_base;
    assign membase_active = video_membase;

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
        .frame_base(selected_frame_base),
        .frame_buffer_select(snapshot_valid ? snapshot_buffer_select : 1'b0),
        .addr(mem_addr),
        .rd(mem_rd),
        .rd_ready(mem_ready),
        .din_valid(mem_data_valid),
        .din(mem_data),
        .fetch_underflow(fetch_underflow),
        .scanout_buffer_select(scanout_buffer_select),
        .mode8(mode8_active),
        .blank(blank_active),
        .flash_phase_active(flash_phase_active),
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
