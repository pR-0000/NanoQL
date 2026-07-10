module ql_zx8301_lite(
    input  wire        reset,
    input  wire        clk_pixel,

    // Minimal CPU-facing register interface, matching the role of the real
    // ZX8301 write-only register at $18063.
    input  wire        clk_bus,
    input  wire        cpu_cs,
    input  wire [7:0]  cpu_data,

    input  wire        visible,
    input  wire        ql_area,
    input  wire        ql_fetch_start,
    input  wire [7:0]  ql_fetch_y,
    input  wire [8:0]  ql_x,
    input  wire [7:0]  ql_y,
    input  wire        flash_phase,

    output wire [18:0] addr,
    output wire        rd,
    input  wire        rd_ready,
    input  wire        din_valid,
    input  wire [15:0] din,

    output wire        fetch_underflow,
    output wire        mode8,
    output wire        blank,
    output wire        membase,
    output wire [23:0] rgb
);

    reg [7:0] mc_stat;

    // The original ZX8301 latches MC_STAT on the falling edge of the bus clock.
    // Keeping that edge here also leaves a clean half-cycle for a future 68000.
    always @(negedge clk_bus) begin
        if (reset)
            mc_stat <= 8'h00;
        else if (cpu_cs)
            mc_stat <= cpu_data;
    end

    // Keep the same bit meanings used by mist-devel/ql/zx8301.v.
    assign membase = mc_stat[7]; // 0=$20000, 1=$28000 in byte address space
    assign mode8   = mc_stat[3]; // 0=512x256 2bpp, 1=256x256 4bpp
    assign blank   = mc_stat[1]; // 0=normal video, 1=blanked video

    ql_video_scanout scanout (
        .reset(reset),
        .clk(clk_pixel),
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
