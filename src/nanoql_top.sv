`define GOWIN

module nanoql_top(
    input  wire       clk_27m,
    output wire [5:0] leds_n,

    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p,

    // Reserved Gowin port names connect to the on-package 64-Mbit SDRAM.
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm
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
    wire [10:0] x;
    wire [9:0] y;
    wire mode8_active;
    wire blank_active;
    wire video_vblank;
    wire fetch_underflow;

    wire [18:0] video_mem_addr;
    wire video_mem_rd;
    wire video_mem_ready;
    wire video_mem_data_valid;
    wire [15:0] video_mem_data;
    wire zx8301_mc_stat_wr;
    wire [7:0] zx8301_mc_stat_data;
    wire zx8302_wr;
    wire [1:0] zx8302_addr;
    wire [1:0] zx8302_ds;
    wire [15:0] zx8302_wdata;
    wire [15:0] zx8302_rdata;
    wire [2:0] cpu_ipl_n;
    wire zx8302_ipc_ready;
    wire bus_mem_req;
    wire bus_mem_we;
    wire [21:0] bus_mem_addr;
    wire [1:0] bus_mem_ds;
    wire [15:0] bus_mem_wdata;
    wire bus_mem_ready;
    wire bus_mem_data_valid;
    wire [15:0] bus_mem_data;
    wire rom_is_diagnostic;
    wire sdram_system_req;
    wire sdram_system_we;
    wire [21:0] sdram_system_addr;
    wire [1:0] sdram_system_ds;
    wire [15:0] sdram_system_wdata;
    wire sdram_system_ready;
    wire sdram_system_data_valid;
    wire [15:0] sdram_system_data;
    wire [23:0] cpu_addr;
    wire [15:0] cpu_data_out;
    wire [15:0] cpu_data_in;
    wire cpu_as_n;
    wire cpu_rw;
    wire cpu_uds_n;
    wire cpu_lds_n;
    wire cpu_dtack_n;
    wire cpu_boot_fail;
    wire cpu_boot_done;
    wire sdram_init_done;
    wire sdram_init_fail;

    ql_sdram_memory sdram_memory (
        .clk(clk_pixel),
        .reset(video_reset),
        .client_addr(video_mem_addr),
        .client_rd(video_mem_rd),
        .client_ready(video_mem_ready),
        .client_data_valid(video_mem_data_valid),
        .client_data(video_mem_data),
        .system_req(sdram_system_req),
        .system_we(sdram_system_we),
        .system_addr(sdram_system_addr),
        .system_ds(sdram_system_ds),
        .system_wdata(sdram_system_wdata),
        .system_ready(sdram_system_ready),
        .system_data_valid(sdram_system_data_valid),
        .system_data(sdram_system_data),
        .sdram_clk(O_sdram_clk),
        .sdram_cke(O_sdram_cke),
        .sdram_cs_n(O_sdram_cs_n),
        .sdram_cas_n(O_sdram_cas_n),
        .sdram_ras_n(O_sdram_ras_n),
        .sdram_wen_n(O_sdram_wen_n),
        .sdram_dq(IO_sdram_dq),
        .sdram_addr(O_sdram_addr),
        .sdram_ba(O_sdram_ba),
        .sdram_dqm(O_sdram_dqm),
        .init_done(sdram_init_done),
        .init_fail(sdram_init_fail)
    );

    ql_video_test ql_video_test (
        .clk_pixel(clk_pixel),
        .reset(video_reset),
        .mem_addr(video_mem_addr),
        .mem_rd(video_mem_rd),
        .mem_ready(video_mem_ready),
        .mem_data_valid(video_mem_data_valid),
        .mem_data(video_mem_data),
        .mc_stat_wr(zx8301_mc_stat_wr),
        .mc_stat_data(zx8301_mc_stat_data),
        .rgb(rgb),
        .mode8_active(mode8_active),
        .blank_active(blank_active),
        .vblank(video_vblank),
        .fetch_underflow(fetch_underflow),
        .x(x),
        .y(y)
    );

    ql_cpu_bus_bridge cpu_bus_bridge (
        .clk(clk_pixel),
        .reset(video_reset),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_dtack_n(cpu_dtack_n),
        .system_req(bus_mem_req),
        .system_we(bus_mem_we),
        .system_addr(bus_mem_addr),
        .system_ds(bus_mem_ds),
        .system_wdata(bus_mem_wdata),
        .system_ready(bus_mem_ready),
        .system_data_valid(bus_mem_data_valid),
        .system_data(bus_mem_data)
    );

    ql_memory_map memory_map (
        .clk(clk_pixel),
        .reset(video_reset),
        .bus_req(bus_mem_req),
        .bus_we(bus_mem_we),
        .bus_addr(bus_mem_addr),
        .bus_ds(bus_mem_ds),
        .bus_wdata(bus_mem_wdata),
        .bus_ready(bus_mem_ready),
        .bus_data_valid(bus_mem_data_valid),
        .bus_data(bus_mem_data),
        .rom_is_diagnostic(rom_is_diagnostic),
        .mc_stat_wr(zx8301_mc_stat_wr),
        .mc_stat_data(zx8301_mc_stat_data),
        .zx8302_wr(zx8302_wr),
        .zx8302_addr(zx8302_addr),
        .zx8302_ds(zx8302_ds),
        .zx8302_wdata(zx8302_wdata),
        .zx8302_rdata(zx8302_rdata),
        .ram_req(sdram_system_req),
        .ram_we(sdram_system_we),
        .ram_addr(sdram_system_addr),
        .ram_ds(sdram_system_ds),
        .ram_wdata(sdram_system_wdata),
        .ram_ready(sdram_system_ready),
        .ram_data_valid(sdram_system_data_valid),
        .ram_data(sdram_system_data)
    );

    ql_zx8302_lite zx8302_lite (
        .clk(clk_pixel),
        .reset(video_reset),
        .vblank(video_vblank),
        .write(zx8302_wr),
        .addr(zx8302_addr),
        .ds(zx8302_ds),
        .wdata(zx8302_wdata),
        .rdata(zx8302_rdata),
        .ipl_n(cpu_ipl_n),
        .ipc_ready(zx8302_ipc_ready)
    );

    ql_cpu_fx68k ql_cpu (
        .clk(clk_pixel),
        .reset(video_reset),
        .enable(sdram_init_done && !sdram_init_fail),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_dtack_n(cpu_dtack_n),
        .cpu_ipl_n(cpu_ipl_n)
    );

    ql_cpu_boot_monitor cpu_boot_monitor (
        .clk(clk_pixel),
        .reset(video_reset),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_dtack_n(cpu_dtack_n),
        .boot_done(cpu_boot_done),
        .boot_fail(cpu_boot_fail)
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
    wire memory_status_area = (x < 11'd16) && (y < 10'd16);
    wire memory_failure = sdram_init_fail ||
                          (rom_is_diagnostic && cpu_boot_fail);
    wire [23:0] memory_status_rgb = memory_failure ? 24'hff2020 :
                                    !sdram_init_done ? 24'hffc020 :
                                    !rom_is_diagnostic ?
                                      (zx8302_ipc_ready ? 24'h20c0c0 : 24'h2080e0) :
                                    cpu_boot_done ? 24'h20e060 : 24'hffc020;
    wire [23:0] hdmi_rgb = memory_status_area ? memory_status_rgb : rgb;

    nanoql_hdmi #(
        .PIXEL_CLOCK(32_000_000)
    ) hdmi_out (
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .reset(video_reset),
        .rgb(hdmi_rgb),
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
    assign leds_n[1] = ~(pll_lock && sdram_init_done &&
                         (rom_is_diagnostic ? cpu_boot_done : zx8302_ipc_ready) &&
                         !memory_failure);
    assign leds_n[2] = ~(fetch_underflow || memory_failure);
    assign leds_n[3] = ~blank_active;
    assign leds_n[4] = ~mode8_active;
    assign leds_n[5] = ~ql_native_frame_div[5];

endmodule



