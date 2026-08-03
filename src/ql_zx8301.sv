// Sinclair QL ZX8301 master-chip model.
//
// Native video timings and MC_STAT behavior follow the MiSTer QL core. The
// HDMI scanout remains clock-domain independent, but QL system timing (VSYNC,
// VBLANK and flashing) is generated here and never from the HDMI frame.
module ql_zx8301 #(
    parameter [31:0] NATIVE_CE_STEP = 32'd939524096
)(
    input  wire        reset,
    input  wire        core_reset,
    input  wire        clk_pixel,

    // CPU-facing write-only MC_STAT register at $18063.
    input  wire        clk_bus,
    input  wire        cpu_cs,
    input  wire [7:0]  cpu_data,

    // HDMI scanout coordinates and line-prefetch trigger.
    input  wire        visible,
    input  wire        ql_area,
    input  wire        ql_fetch_start,
    input  wire [7:0]  ql_fetch_y,
    input  wire [8:0]  ql_x,
    input  wire [7:0]  ql_y,

    output wire [18:0] addr,
    output wire        rd,
    input  wire        rd_ready,
    input  wire        din_valid,
    input  wire [15:0] din,

    output wire        fetch_underflow,
    output wire        mode8,
    output wire        blank,
    output wire        membase,
    output wire        ntsc,
    output wire [23:0] rgb,

    // Native QL raster. HSYNC is active high as in QL_MiSTer; VSYNC is the
    // positive pulse routed to the ZX8302 frame-interrupt input.
    output reg         native_ce,
    output reg  [9:0]  native_h,
    output reg  [9:0]  native_v,
    output reg         native_hs,
    output reg         native_vs,
    output reg         native_hblank,
    output reg         native_vblank,
    output reg         native_frame
);

    localparam [9:0] H_VISIBLE = 10'd512;
    localparam [9:0] V_VISIBLE = 10'd256;

    // QL_MiSTer PAL timing: 512 + 24 + 72 + 64 = 672 pixels,
    // 256 + 25 + 6 + 25 = 312 lines (50.080 Hz at 10.5 MHz).
    localparam [9:0] PAL_HFP = 10'd24;
    localparam [9:0] PAL_HSW = 10'd72;
    localparam [9:0] PAL_HBP = 10'd64;
    localparam [9:0] PAL_VFP = 10'd25;
    localparam [9:0] PAL_VSW = 10'd6;
    localparam [9:0] PAL_VBP = 10'd25;

    // Later CLA2345 ZX8301 revisions support NTSC through MC_STAT bit 6.
    localparam [9:0] NTSC_HFP = 10'd34;
    localparam [9:0] NTSC_HSW = 10'd64;
    localparam [9:0] NTSC_HBP = 10'd54;
    localparam [9:0] NTSC_VFP = 10'd2;
    localparam [9:0] NTSC_VSW = 10'd2;
    localparam [9:0] NTSC_VBP = 10'd2;

    reg [7:0] mc_stat;

    // The physical ZX8301 samples MC_STAT on the falling bus-clock edge.
    always @(negedge clk_bus) begin
        if (core_reset)
            mc_stat <= 8'h00;
        else if (cpu_cs)
            mc_stat <= cpu_data;
    end

    assign membase = mc_stat[7]; // 0=$20000, 1=$28000
    assign ntsc    = mc_stat[6]; // implemented by later ZX8301 revisions
    assign mode8   = mc_stat[3]; // 0=512x256 2bpp, 1=256x256 4bpp
    assign blank   = mc_stat[1]; // force RGB black without stopping timing

    wire [9:0] hfp = ntsc ? NTSC_HFP : PAL_HFP;
    wire [9:0] hsw = ntsc ? NTSC_HSW : PAL_HSW;
    wire [9:0] hbp = ntsc ? NTSC_HBP : PAL_HBP;
    wire [9:0] vfp = ntsc ? NTSC_VFP : PAL_VFP;
    wire [9:0] vsw = ntsc ? NTSC_VSW : PAL_VSW;
    wire [9:0] vbp = ntsc ? NTSC_VBP : PAL_VBP;
    wire [9:0] h_total = H_VISIBLE + hfp + hsw + hbp;
    wire [9:0] v_total = V_VISIBLE + vfp + vsw + vbp;

    // 48 MHz * 939524096 / 2^32 = exactly 10.500000 MHz. The native raster
    // therefore remains independent of the selected 68000 speed.
    reg [31:0] ce_accum;
    wire [32:0] ce_sum = {1'b0, ce_accum} +
                         {1'b0, NATIVE_CE_STEP};
    wire native_ce_tick = ce_sum[32];

    always @(posedge clk_bus) begin
        if (reset) begin
            ce_accum <= 32'd0;
            native_ce <= 1'b0;
        end else begin
            ce_accum <= ce_sum[31:0];
            native_ce <= native_ce_tick;
        end
    end

    reg [5:0] flash_count;
    reg       flash_phase;

    // Counter transitions intentionally match rtl/zx8301.v from QL_MiSTer:
    // vertical timing advances at the beginning of HSYNC, while HBLANK and
    // VBLANK change at the visible-area boundaries.
    always @(posedge clk_bus) begin
        native_frame <= 1'b0;

        if (reset) begin
            native_h <= 10'd0;
            native_v <= 10'd0;
            native_hs <= 1'b0;
            native_vs <= 1'b0;
            native_hblank <= 1'b0;
            native_vblank <= 1'b0;
            native_frame <= 1'b0;
            flash_count <= 6'd0;
            flash_phase <= 1'b0;
        end else if (native_ce_tick) begin
            if (native_h == h_total - 10'd1)
                native_h <= 10'd0;
            else
                native_h <= native_h + 10'd1;

            if (native_h == H_VISIBLE + hfp)
                native_hs <= 1'b1;
            if (native_h == H_VISIBLE + hfp + hsw)
                native_hs <= 1'b0;

            if (native_h == 10'd0) begin
                native_hblank <= 1'b0;
                native_vblank <= (native_v >= V_VISIBLE);
            end
            if (native_h == H_VISIBLE)
                native_hblank <= 1'b1;

            if (native_h == H_VISIBLE + hfp) begin
                if (native_v == v_total - 10'd1) begin
                    native_v <= 10'd0;
                    native_frame <= 1'b1;
                end else begin
                    native_v <= native_v + 10'd1;
                end

                if (native_v == V_VISIBLE + vfp) begin
                    native_vs <= 1'b1;
                    if (flash_count == 6'd25) begin
                        flash_count <= 6'd0;
                        flash_phase <= ~flash_phase;
                    end else begin
                        flash_count <= flash_count + 6'd1;
                    end
                end

                if (native_v == V_VISIBLE + vfp + vsw)
                    native_vs <= 1'b0;
            end
        end
    end

    ql_video_scanout scanout (
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
        .membase(membase),
        .flash_phase(flash_phase),
        .addr(addr),
        .rd(rd),
        .rd_ready(rd_ready),
        .din_valid(din_valid),
        .din(din),
        .fetch_underflow(fetch_underflow),
        .rgb(rgb)
    );

endmodule
