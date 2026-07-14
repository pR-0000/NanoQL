`define GOWIN

module nanoql_top(
    input  wire       clk_27m,
    input  wire       key_s1,
    output wire [5:0] leds_n,

    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p,

    // SPI connection to the on-board BL616 on revisions 3921/3923.
    input  wire       spi_sclk,
    input  wire       spi_csn,
    input  wire       spi_dat,
    output wire       spi_dir,
    output wire       spi_irqn,

    // On-board microSD interface.
    output wire       sd_clk,
    inout  wire       sd_cmd,
    inout  wire [3:0] sd_dat,

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
    wire clk_hdmi_x5;
    wire clk_hdmi;
    wire pll_hdmi_lock;

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

    pll_371m pll_720p (
        .clkout(clk_hdmi_x5),
        .lock(pll_hdmi_lock),
        .clkin(clk_27m)
    );

    Gowin_CLKDIV clk_hdmi_div_5 (
        .hclkin(clk_hdmi_x5),
        .resetn(pll_hdmi_lock),
        .clkout(clk_hdmi)
    );

    reg [15:0] reset_shift = 16'hffff;
    always @(posedge clk_pixel or negedge pll_lock or negedge pll_hdmi_lock) begin
        if (!pll_lock || !pll_hdmi_lock)
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
    wire zx8302_write_done;
    wire [2:0] cpu_ipl_n;
    wire zx8302_ipc_ready;
    wire ql_audio;
    wire bus_mem_req;
    wire bus_mem_we;
    wire [21:0] bus_mem_addr;
    wire [1:0] bus_mem_ds;
    wire [15:0] bus_mem_wdata;
    wire bus_mem_ready;
    wire bus_mem_data_valid;
    wire [15:0] bus_mem_data;
    wire bus_mem_write_done;
    wire rom_is_diagnostic;
    wire rom_is_dynamic;
    wire mapped_rom_req;
    wire [14:0] mapped_rom_addr;
    wire mapped_rom_ready;
    wire mapped_rom_data_valid;
    wire [15:0] mapped_rom_data;
    wire mapped_sdram_req;
    wire mapped_sdram_we;
    wire [21:0] mapped_sdram_addr;
    wire [1:0] mapped_sdram_ds;
    wire [15:0] mapped_sdram_wdata;
    wire mapped_sdram_ready;
    wire mapped_sdram_data_valid;
    wire [15:0] mapped_sdram_data;
    wire mapped_sdram_write_done;
    wire sdram_system_req;
    wire sdram_system_we;
    wire [21:0] sdram_system_addr;
    wire [1:0] sdram_system_ds;
    wire [15:0] sdram_system_wdata;
    wire sdram_system_ready;
    wire sdram_system_data_valid;
    wire [15:0] sdram_system_data;
    wire sdram_system_write_done;
    wire [23:0] cpu_addr;
    wire [15:0] cpu_data_out;
    wire [15:0] cpu_data_in;
    wire cpu_as_n;
    wire cpu_rw;
    wire cpu_uds_n;
    wire cpu_lds_n;
    wire cpu_dtack_n;
    wire [2:0] cpu_fc;
    wire cpu_ce_bus_p;
    wire cpu_ce_bus_n;
    reg ipc_ce_11m;
    reg [15:0] ipc_ce_accumulator;
    wire ram_delay_dtack;
    wire cpu_boot_fail;
    wire cpu_boot_done;
    wire cpu_stress_pass_pulse;
    wire sdram_init_done;
    wire sdram_init_fail;
    wire ql_native_ce;
    wire ql_native_hs;
    wire ql_native_vs;
    wire ql_native_active;
    wire ql_native_vblank;
    wire ql_native_frame;
    wire [9:0] ql_native_h;
    wire [9:0] ql_native_v;
    wire ql_system_reset;
    wire cpu_run_enable;

    wire mcu_sys_strobe;
    wire mcu_hid_strobe;
    wire mcu_osd_strobe;
    wire mcu_sdc_strobe;
    wire mcu_link_strobe;
    wire mcu_start;
    wire [7:0] mcu_data;
    wire [7:0] companion_sys_data;
    wire [7:0] companion_hid_data;
    wire [7:0] companion_sd_data;
    wire [7:0] companion_link_data;
    wire [63:0] companion_keyboard_matrix;
    wire companion_key_event;
    wire companion_key_press_event;
    wire companion_miso;
    wire companion_sd_irq;
    wire companion_sd_iack;
    wire [1:0] companion_system_reset;
    wire [1:0] companion_video_aspect;
    wire companion_status_seen;
    wire companion_config_seen;
    reg [1:0] key_s1_sync;
    reg key_s1_latched;
    reg companion_sdc_seen;
    reg companion_any_strobe_seen;
    reg companion_sys_strobe_seen;
    reg companion_sys_start_seen;
    reg [1:0] companion_csn_sync;
    reg companion_raw_spi_seen;
    wire [63:0] companion_image_size;
    wire [7:0] companion_image_mounted;
    wire companion_sd_busy;
    wire companion_sd_done;
    wire companion_sd_byte_valid;
    wire [8:0] companion_sd_byte_addr;
    wire [7:0] companion_sd_byte;
    wire rom_sd_read_start;
    wire [31:0] rom_sd_sector;
    wire rom_loader_req;
    wire rom_loader_we;
    wire [21:0] rom_loader_addr;
    wire [1:0] rom_loader_ds;
    wire [15:0] rom_loader_wdata;
    wire rom_loader_ready;
    wire rom_loader_data_valid;
    wire [15:0] rom_loader_data;
    wire rom_loader_write_done;
    wire rom_store_req;
    wire rom_store_we;
    wire [14:0] rom_store_addr;
    wire [15:0] rom_store_wdata;
    wire rom_store_ready;
    wire rom_store_data_valid;
    wire [15:0] rom_store_data;
    wire rom_store_write_done;
    wire rom_loading;
    wire rom_load_done;
    wire rom_load_fail;
    wire [7:0] rom_sector_progress;
    wire rom_loader_owns_store = rom_is_dynamic && !rom_load_done;
    wire host_mem_req;
    wire host_mem_we;
    wire [21:0] host_mem_addr;
    wire [1:0] host_mem_ds;
    wire [15:0] host_mem_wdata;
    wire host_mem_ready;
    wire host_mem_write_done;
    wire host_mem_data_valid;
    wire [15:0] host_mem_rdata;
    wire host_cpu_hold;
    wire host_boot_vectors_active;
    wire [31:0] host_boot_ssp;
    wire [31:0] host_boot_pc;
    wire host_restart_pulse;

    // Keep QL RAM/video in SDRAM. The runtime-loaded ROM has its own BSRAM,
    // matching the separate dpram ROM path used by QL MiSTer.
    // NanoQL Link owns this port only while the 68000 is explicitly held.
    assign sdram_system_req = host_cpu_hold ? host_mem_req : mapped_sdram_req;
    assign sdram_system_we = host_cpu_hold ? host_mem_we : mapped_sdram_we;
    assign sdram_system_addr = host_cpu_hold ? host_mem_addr : mapped_sdram_addr;
    assign sdram_system_ds = host_cpu_hold ? host_mem_ds : mapped_sdram_ds;
    assign sdram_system_wdata = host_cpu_hold ? host_mem_wdata :
                                                   mapped_sdram_wdata;
    assign mapped_sdram_ready = !host_cpu_hold && sdram_system_ready;
    assign mapped_sdram_data_valid = !host_cpu_hold &&
                                     sdram_system_data_valid;
    assign mapped_sdram_data = sdram_system_data;
    assign mapped_sdram_write_done = !host_cpu_hold &&
                                     sdram_system_write_done;
    assign host_mem_ready = host_cpu_hold && sdram_system_ready;
    assign host_mem_write_done = host_cpu_hold && sdram_system_write_done;
    assign host_mem_data_valid = host_cpu_hold && sdram_system_data_valid;
    assign host_mem_rdata = sdram_system_data;

    assign rom_store_req = rom_loader_owns_store ?
                           rom_loader_req : mapped_rom_req;
    assign rom_store_we = rom_loader_owns_store && rom_loader_we;
    assign rom_store_addr = rom_loader_owns_store ?
                            rom_loader_addr[14:0] : mapped_rom_addr;
    assign rom_store_wdata = rom_loader_wdata;
    assign mapped_rom_ready = !rom_loader_owns_store && rom_store_ready;
    assign mapped_rom_data_valid = !rom_loader_owns_store &&
                                   rom_store_data_valid;
    assign mapped_rom_data = rom_store_data;
    assign rom_loader_ready = rom_loader_owns_store && rom_store_ready;
    assign rom_loader_data_valid = rom_loader_owns_store &&
                                   rom_store_data_valid;
    assign rom_loader_data = rom_store_data;
    assign rom_loader_write_done = rom_loader_owns_store &&
                                   rom_store_write_done;

    mcu_spi companion_spi (
        .clk(clk_pixel),
        .reset(video_reset),
        .spi_io_ss(spi_csn),
        .spi_io_clk(spi_sclk),
        .spi_io_din(spi_dat),
        .spi_io_dout(companion_miso),
        .mcu_sys_strobe(mcu_sys_strobe),
        .mcu_hid_strobe(mcu_hid_strobe),
        .mcu_osd_strobe(mcu_osd_strobe),
        .mcu_sdc_strobe(mcu_sdc_strobe),
        .mcu_link_strobe(mcu_link_strobe),
        .mcu_start(mcu_start),
        .mcu_sys_din(companion_sys_data),
        .mcu_hid_din(companion_hid_data),
        .mcu_osd_din(8'h00),
        .mcu_sdc_din(companion_sd_data),
        .mcu_link_din(companion_link_data),
        .mcu_dout(mcu_data)
    );

    ql_host_link host_link (
        .clk(clk_pixel),
        .reset(video_reset),
        .data_strobe(mcu_link_strobe),
        .data_start(mcu_start),
        .data_in(mcu_data),
        .data_out(companion_link_data),
        .sdram_ready(sdram_init_done && !sdram_init_fail),
        .mem_req(host_mem_req),
        .mem_we(host_mem_we),
        .mem_addr(host_mem_addr),
        .mem_ds(host_mem_ds),
        .mem_wdata(host_mem_wdata),
        .mem_ready(host_mem_ready),
        .mem_write_done(host_mem_write_done),
        .mem_data_valid(host_mem_data_valid),
        .mem_rdata(host_mem_rdata),
        .cpu_addr(cpu_addr),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_dtack_n(cpu_dtack_n),
        .cpu_fc(cpu_fc),
        .cpu_hold(host_cpu_hold),
        .boot_vectors_active(host_boot_vectors_active),
        .boot_ssp(host_boot_ssp),
        .boot_pc(host_boot_pc),
        .restart_pulse(host_restart_pulse)
    );

    assign spi_dir = companion_miso;

    always @(posedge clk_pixel) begin
        if (video_reset) begin
            key_s1_sync <= 2'b00;
            key_s1_latched <= 1'b0;
        end else begin
            key_s1_sync <= {key_s1_sync[0], key_s1};
            if (key_s1_sync[1])
                key_s1_latched <= 1'b1;
        end
    end

    ql_companion_sysctrl companion_sysctrl (
        .clk(clk_pixel),
        .reset(video_reset),
        .data_strobe(mcu_sys_strobe),
        .data_start(mcu_start),
        .data_in(mcu_data),
        .data_out(companion_sys_data),
        .sd_irq(companion_sd_irq),
        .sd_iack(companion_sd_iack),
        .int_out_n(spi_irqn),
        .buttons({1'b0, key_s1_latched}),
        .system_reset(companion_system_reset),
        .video_aspect(companion_video_aspect),
        .status_seen(companion_status_seen),
        .config_seen(companion_config_seen)
    );

    ql_companion_hid companion_hid (
        .clk(clk_pixel),
        .reset(video_reset),
        .data_strobe(mcu_hid_strobe),
        .data_start(mcu_start),
        .data_in(mcu_data),
        .data_out(companion_hid_data),
        .matrix(companion_keyboard_matrix),
        .key_event(companion_key_event),
        .key_press_event(companion_key_press_event)
    );

    always @(posedge clk_pixel) begin
        if (video_reset) begin
            companion_sdc_seen <= 1'b0;
            companion_any_strobe_seen <= 1'b0;
            companion_sys_strobe_seen <= 1'b0;
            companion_sys_start_seen <= 1'b0;
            companion_csn_sync <= 2'b11;
            companion_raw_spi_seen <= 1'b0;
        end else begin
            companion_csn_sync <= {companion_csn_sync[0], spi_csn};
            if (!companion_csn_sync[1])
                companion_raw_spi_seen <= 1'b1;
            if (mcu_sdc_strobe)
                companion_sdc_seen <= 1'b1;
            if (mcu_sys_strobe || mcu_hid_strobe ||
                mcu_osd_strobe || mcu_sdc_strobe)
                companion_any_strobe_seen <= 1'b1;
            if (mcu_sys_strobe)
                companion_sys_strobe_seen <= 1'b1;
            if (mcu_sys_strobe && mcu_start) begin
                companion_sys_start_seen <= 1'b1;
            end
        end
    end

    sd_card #(
        .CLK_DIV(3'd0)
    ) companion_sd_card (
        .rstn(!video_reset),
        .clk(clk_pixel),
        .sdclk(sd_clk),
        .sdcmd(sd_cmd),
        .sddat(sd_dat),
        .data_strobe(mcu_sdc_strobe),
        .data_start(mcu_start),
        .data_in(mcu_data),
        .data_out(companion_sd_data),
        .irq(companion_sd_irq),
        .iack(companion_sd_iack),
        .image_size(companion_image_size),
        .image_mounted(companion_image_mounted),
        .rstart({7'd0, rom_sd_read_start}),
        .wstart(8'd0),
        .rsector(rom_sd_sector),
        .rsrc(),
        .rbusy(companion_sd_busy),
        .rdone(companion_sd_done),
        .inbyte(8'd0),
        .outen(companion_sd_byte_valid),
        .outaddr(companion_sd_byte_addr),
        .outbyte(companion_sd_byte)
    );

    ql_sd_rom_loader rom_loader (
        .clk(clk_pixel),
        .reset(video_reset),
        .enable(rom_is_dynamic && sdram_init_done && !sdram_init_fail),
        .image_mounted(companion_image_mounted[0]),
        .image_size(companion_image_size),
        .sd_read_start(rom_sd_read_start),
        .sd_sector(rom_sd_sector),
        .sd_busy(companion_sd_busy),
        .sd_done(companion_sd_done),
        .sd_byte_valid(companion_sd_byte_valid),
        .sd_byte_addr(companion_sd_byte_addr),
        .sd_byte(companion_sd_byte),
        .mem_req(rom_loader_req),
        .mem_we(rom_loader_we),
        .mem_addr(rom_loader_addr),
        .mem_ds(rom_loader_ds),
        .mem_wdata(rom_loader_wdata),
        .mem_ready(rom_loader_ready),
        .mem_data_valid(rom_loader_data_valid),
        .mem_data(rom_loader_data),
        .mem_write_done(rom_loader_write_done),
        .loading(rom_loading),
        .loaded(rom_load_done),
        .failed(rom_load_fail),
        .sector_progress(rom_sector_progress)
    );

    ql_sd_rom_memory rom_memory (
        .clk(clk_pixel),
        .reset(video_reset),
        .req(rom_store_req),
        .we(rom_store_we),
        .addr(rom_store_addr),
        .wdata(rom_store_wdata),
        .ready(rom_store_ready),
        .data_valid(rom_store_data_valid),
        .data(rom_store_data),
        .write_done(rom_store_write_done)
    );

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
        .system_write_done(sdram_system_write_done),
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
        .clk_bus(clk_pixel),
        .clk_pixel(clk_hdmi),
        .reset(video_reset),
        .core_reset(ql_system_reset),
        .aspect_mode(companion_video_aspect),
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

    wire ql_core_ready = sdram_init_done && !sdram_init_fail &&
                         (!rom_is_dynamic ||
                          (rom_load_done &&
                           (companion_system_reset == 2'd0)));

    // The MiSTer core keeps reset asserted for thousands of emulated bus
    // cycles. Give fx68k, the 8049 and both ZX interfaces the same clean
    // startup interval after RAM and the microSD ROM are ready.
    reg [14:0] ql_reset_count = 15'h7fff;
    always @(posedge clk_pixel) begin
        if (video_reset || !ql_core_ready || host_cpu_hold ||
            host_restart_pulse)
            ql_reset_count <= 15'h7fff;
        else if (ql_reset_count != 15'd0)
            ql_reset_count <= ql_reset_count - 15'd1;
    end

    assign ql_system_reset = video_reset || host_cpu_hold ||
                             (ql_reset_count != 15'd0);
    assign cpu_run_enable = ql_core_ready && !ql_system_reset;

    // 31.8 MHz * 22668 / 65536 = 11.0002 MHz. QL_MiSTer uses the same
    // fractional-enable scheme for the 8049 rather than a coarse divider.
    wire [16:0] ipc_ce_sum = {1'b0, ipc_ce_accumulator} + 17'd22668;
    // Register the IPC enable one cycle before the T48 consumes it. This keeps
    // MiSTer's phase separation while remaining in Gowin's primary domain.
    always @(posedge clk_pixel) begin
        if (ql_system_reset) begin
            ipc_ce_accumulator <= 16'd0;
            ipc_ce_11m <= 1'b0;
        end else begin
            ipc_ce_accumulator <= ipc_ce_sum[15:0];
            ipc_ce_11m <= ipc_ce_sum[16];
        end
    end

    ql_timing ql_bus_timing (
        .clk_sys(clk_pixel),
        .reset(ql_system_reset),
        .enable(cpu_run_enable),
        .ce_bus_p(cpu_ce_bus_p),
        .vblank(ql_native_vblank),
        .cpu_uds(!cpu_uds_n),
        .cpu_lds(!cpu_lds_n),
        .cpu_rw(cpu_rw),
        .cpu_rom(cpu_addr[23:16] == 8'h00),
        .ram_delay_dtack(ram_delay_dtack)
    );

    ql_cpu_bus_bridge cpu_bus_bridge (
        .clk(clk_pixel),
        .reset(ql_system_reset),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_iack(cpu_fc == 3'b111),
        .cpu_dtack_n(cpu_dtack_n),
        .timing_delay(ram_delay_dtack),
        .ce_bus_p(cpu_ce_bus_p),
        .system_req(bus_mem_req),
        .system_we(bus_mem_we),
        .system_addr(bus_mem_addr),
        .system_ds(bus_mem_ds),
        .system_wdata(bus_mem_wdata),
        .system_ready(bus_mem_ready),
        .system_data_valid(bus_mem_data_valid),
        .system_data(bus_mem_data),
        .system_write_done(bus_mem_write_done)
    );

    ql_memory_map memory_map (
        .clk(clk_pixel),
        .reset(ql_system_reset),
        .bus_req(bus_mem_req),
        .bus_we(bus_mem_we),
        .bus_addr(bus_mem_addr),
        .bus_ds(bus_mem_ds),
        .bus_wdata(bus_mem_wdata),
        .bus_ready(bus_mem_ready),
        .bus_data_valid(bus_mem_data_valid),
        .bus_data(bus_mem_data),
        .bus_write_done(bus_mem_write_done),
        .rom_is_diagnostic(rom_is_diagnostic),
        .rom_is_dynamic(rom_is_dynamic),
        .boot_vectors_active(host_boot_vectors_active),
        .boot_ssp(host_boot_ssp),
        .boot_pc(host_boot_pc),
        .dynamic_rom_req(mapped_rom_req),
        .dynamic_rom_addr(mapped_rom_addr),
        .dynamic_rom_ready(mapped_rom_ready),
        .dynamic_rom_data_valid(mapped_rom_data_valid),
        .dynamic_rom_data(mapped_rom_data),
        .mc_stat_wr(zx8301_mc_stat_wr),
        .mc_stat_data(zx8301_mc_stat_data),
        .zx8302_wr(zx8302_wr),
        .zx8302_addr(zx8302_addr),
        .zx8302_ds(zx8302_ds),
        .zx8302_wdata(zx8302_wdata),
        .zx8302_rdata(zx8302_rdata),
        .zx8302_write_done(zx8302_write_done),
        .ram_req(mapped_sdram_req),
        .ram_we(mapped_sdram_we),
        .ram_addr(mapped_sdram_addr),
        .ram_ds(mapped_sdram_ds),
        .ram_wdata(mapped_sdram_wdata),
        .ram_ready(mapped_sdram_ready),
        .ram_data_valid(mapped_sdram_data_valid),
        .ram_data(mapped_sdram_data),
        .ram_write_done(mapped_sdram_write_done)
    );

    ql_zx8302 zx8302 (
        .clk(clk_pixel),
        .reset(ql_system_reset),
        .ce_11m(ipc_ce_11m),
        .ce_bus_n(cpu_ce_bus_n),
        .vs(ql_native_vs),
        .keyboard_matrix(companion_keyboard_matrix),
        .cpu_write(zx8302_wr),
        .cpu_addr(zx8302_addr),
        .cpu_ds_n(zx8302_ds),
        .cpu_din(zx8302_wdata),
        .cpu_write_done(zx8302_write_done),
        .cpu_dout(zx8302_rdata),
        .ipl_n(cpu_ipl_n),
        .ipc_ready(zx8302_ipc_ready),
        .audio(ql_audio)
    );

    ql_cpu_fx68k ql_cpu (
        .clk(clk_pixel),
        .reset(ql_system_reset),
        .enable(cpu_run_enable),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_dtack_n(cpu_dtack_n),
        .cpu_ipl_n(cpu_ipl_n),
        .cpu_fc(cpu_fc),
        .ce_bus_p(cpu_ce_bus_p),
        .ce_bus_n(cpu_ce_bus_n)
    );

    ql_cpu_boot_monitor cpu_boot_monitor (
        .clk(clk_pixel),
        .reset(ql_system_reset),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_dtack_n(cpu_dtack_n),
        .boot_done(cpu_boot_done),
        .boot_fail(cpu_boot_fail),
        .stress_pass_pulse(cpu_stress_pass_pulse)
    );

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
    reg stress_pass_phase = 1'b0;
    always @(posedge clk_pixel or posedge video_reset) begin
        if (video_reset) begin
            ql_native_frame_div <= 6'd0;
            stress_pass_phase <= 1'b0;
        end else begin
            if (ql_native_frame)
                ql_native_frame_div <= ql_native_frame_div + 6'd1;
            if (cpu_stress_pass_pulse)
                stress_pass_phase <= ~stress_pass_phase;
        end
    end
    wire memory_status_area = (x < 11'd16) && (y < 10'd16);
    wire memory_failure = sdram_init_fail ||
                          (rom_is_diagnostic && cpu_boot_fail) ||
                          (rom_is_dynamic && rom_load_fail);
    wire [23:0] memory_status_rgb = memory_failure ? 24'hff2020 :
                                    !sdram_init_done ? 24'hffc020 :
                                    rom_is_dynamic ?
                                      (rom_load_done ? 24'h20e060 :
                                       rom_loading ? 24'h20c0c0 :
                                       !companion_raw_spi_seen ? 24'h0000ff :
                                       !companion_any_strobe_seen ? 24'hff00ff :
                                       !companion_sys_strobe_seen ? 24'hff8000 :
                                       !companion_status_seen ? 24'hff4080 :
                                       !companion_config_seen ? 24'h8000ff :
                                       !companion_sdc_seen ? 24'he0c020 :
                                       24'he0e0e0) :
                                    !rom_is_diagnostic ?
                                      (zx8302_ipc_ready ? 24'h20c0c0 : 24'h2080e0) :
                                    cpu_boot_done ?
                                      (stress_pass_phase ? 24'h20e060 : 24'h20a040) :
                                      24'hffc020;
    // Dynamic-ROM builds use the complete visible output as a readable boot
    // status display. The ROM mount event is retained by the loader, so a ROM
    // announced while SDRAM initializes is retried automatically.
    wire dynamic_rom_wait = rom_is_dynamic &&
                            (!rom_load_done || companion_system_reset != 2'd0);
    reg [26:0] companion_wait_timer = 27'd0;
    always @(posedge clk_pixel or posedge video_reset) begin
        if (video_reset || !dynamic_rom_wait || rom_loading)
            companion_wait_timer <= 27'd0;
        else if (!companion_wait_timer[26])
            companion_wait_timer <= companion_wait_timer + 27'd1;
    end

    localparam [3:0] BOOT_MEMORY      = 4'd0;
    localparam [3:0] BOOT_WAIT        = 4'd1;
    localparam [3:0] BOOT_BL616       = 4'd2;
    localparam [3:0] BOOT_ROM_MISSING = 4'd3;
    localparam [3:0] BOOT_LOADING     = 4'd4;
    localparam [3:0] BOOT_ROM_FAILED  = 4'd5;
    localparam [3:0] BOOT_RESET_HELD  = 4'd6;
    localparam [3:0] BOOT_SDRAM_FAIL  = 4'd7;
    reg [3:0] boot_status;
    always @(*) begin
        if (sdram_init_fail)
            boot_status = BOOT_SDRAM_FAIL;
        else if (!sdram_init_done)
            boot_status = BOOT_MEMORY;
        else if (rom_load_fail)
            boot_status = BOOT_ROM_FAILED;
        else if (rom_loading)
            boot_status = BOOT_LOADING;
        else if (rom_load_done && companion_system_reset != 2'd0)
            boot_status = BOOT_RESET_HELD;
        else if (!companion_wait_timer[26])
            boot_status = BOOT_WAIT;
        else if (!companion_raw_spi_seen || !companion_status_seen)
            boot_status = BOOT_BL616;
        else
            boot_status = BOOT_ROM_MISSING;
    end

    wire [23:0] companion_diag_rgb;
    ql_boot_status boot_status_display (
        .clk(clk_hdmi),
        .reset(video_reset),
        .x(x),
        .y(y),
        .status(boot_status),
        .progress(rom_sector_progress),
        .rgb(companion_diag_rgb)
    );

    // After a USB key event, briefly expose the four stages needed by QDOS:
    // HID event, non-empty matrix, 50 Hz IRQ acknowledgement, IPC command.
    wire vblank_ack_pulse = zx8302_wr && (zx8302_addr == 2'b10) &&
                            !zx8302_ds[0] && zx8302_wdata[3];
    wire ipc_command_pulse = zx8302_wr && (zx8302_addr == 2'b01) &&
                             !zx8302_ds[0];
    reg [15:0] vblank_ack_count = 16'd0;
    reg [15:0] ipc_command_count = 16'd0;
    reg [15:0] key_vblank_snapshot = 16'd0;
    reg [15:0] key_ipc_snapshot = 16'd0;
    reg [26:0] keyboard_diag_timer = 27'd0;
    reg [25:0] keyboard_diag_collect_timer = 26'd0;
    reg keyboard_diag_collecting = 1'b0;
    reg keyboard_matrix_seen = 1'b0;
    reg [15:0] ipc_write_idle = 16'hffff;
    reg [1:0] ipc_command_bit_count = 2'd0;
    reg [3:0] ipc_command_shift = 4'd0;
    reg ipc_status_command_seen = 1'b0;
    reg ipc_keyboard_command_seen = 1'b0;
    reg ipc_keyboard_response = 1'b0;
    reg [4:0] ipc_keyboard_read_count = 5'd0;
    reg [7:0] ipc_keyboard_keycode_shift = 8'd0;
    reg [7:0] ipc_keyboard_keycode = 8'd0;
    reg ipc_data_read_armed = 1'b0;
    reg [3:0] ipc_keyboard_count_shift = 4'd0;
    reg [3:0] ipc_keyboard_count = 4'd0;
    reg [3:0] ipc_keyboard_modifier_shift = 4'd0;
    reg [3:0] ipc_keyboard_modifier = 4'd0;
    reg [24:0] qdos_monitor_timer = 25'd0;
    reg qdos_ascii_write_seen = 1'b0;
    reg qdos_ascii_read_seen = 1'b0;
    reg qdos_screen_write_seen = 1'b0;
    reg [21:0] qdos_ascii_address = 22'd0;
    reg [1:0] qdos_ascii_ds = 2'b11;
    reg ipc_keyboard_result_latched = 1'b0;

    wire zx8302_status_read = bus_mem_data_valid && !bus_mem_we &&
                              (bus_mem_addr == 22'h00c010) &&
                              !bus_mem_ds[1];
    wire ipc_serial_data_read = zx8302_status_read && ipc_data_read_armed;
    wire [3:0] ipc_command_next = {ipc_command_shift[2:0],
                                   zx8302_wdata[1]};
    wire [3:0] ipc_keyboard_count_next = {
        ipc_keyboard_count_shift[2:0], bus_mem_data[15]
    };
    wire cpu_write_p = bus_mem_req && bus_mem_we &&
                       (bus_mem_addr >= 22'h010000) &&
                       (bus_mem_addr <= 22'h01ffff) &&
                       ((bus_mem_ds == 2'b01) ||
                        (bus_mem_ds == 2'b10)) &&
                       ((!bus_mem_ds[1] &&
                         ((bus_mem_wdata[15:8] == 8'h70) ||
                          (bus_mem_wdata[15:8] == 8'h50))) ||
                        (!bus_mem_ds[0] &&
                         ((bus_mem_wdata[7:0] == 8'h70) ||
                          (bus_mem_wdata[7:0] == 8'h50))));
    wire cpu_read_p = bus_mem_data_valid && !bus_mem_we &&
                      (bus_mem_addr >= 22'h010000) &&
                      (bus_mem_addr <= 22'h01ffff) &&
                      ((bus_mem_ds == 2'b01) ||
                       (bus_mem_ds == 2'b10)) &&
                      ((!bus_mem_ds[1] &&
                        ((bus_mem_data[15:8] == 8'h70) ||
                         (bus_mem_data[15:8] == 8'h50))) ||
                       (!bus_mem_ds[0] &&
                        ((bus_mem_data[7:0] == 8'h70) ||
                         (bus_mem_data[7:0] == 8'h50))));
    wire cpu_screen_write = bus_mem_req && bus_mem_we &&
                            (bus_mem_addr >= 22'h010000) &&
                            (bus_mem_addr <= 22'h013fff);

    always @(posedge clk_pixel or posedge video_reset) begin
        if (video_reset) begin
            vblank_ack_count <= 16'd0;
            ipc_command_count <= 16'd0;
            key_vblank_snapshot <= 16'd0;
            key_ipc_snapshot <= 16'd0;
            keyboard_diag_timer <= 27'd0;
            keyboard_diag_collect_timer <= 26'd0;
            keyboard_diag_collecting <= 1'b0;
            keyboard_matrix_seen <= 1'b0;
            ipc_write_idle <= 16'hffff;
            ipc_command_bit_count <= 2'd0;
            ipc_command_shift <= 4'd0;
            ipc_status_command_seen <= 1'b0;
            ipc_keyboard_command_seen <= 1'b0;
            ipc_keyboard_response <= 1'b0;
            ipc_keyboard_read_count <= 5'd0;
            ipc_keyboard_keycode_shift <= 8'd0;
            ipc_keyboard_keycode <= 8'd0;
            ipc_data_read_armed <= 1'b0;
            ipc_keyboard_count_shift <= 4'd0;
            ipc_keyboard_count <= 4'd0;
            ipc_keyboard_modifier_shift <= 4'd0;
            ipc_keyboard_modifier <= 4'd0;
            qdos_monitor_timer <= 25'd0;
            qdos_ascii_write_seen <= 1'b0;
            qdos_ascii_read_seen <= 1'b0;
            qdos_screen_write_seen <= 1'b0;
            qdos_ascii_address <= 22'd0;
            qdos_ascii_ds <= 2'b11;
            ipc_keyboard_result_latched <= 1'b0;
        end else begin
            if (vblank_ack_pulse)
                vblank_ack_count <= vblank_ack_count + 16'd1;
            if (ipc_command_pulse)
                ipc_command_count <= ipc_command_count + 16'd1;

            if (ipc_command_pulse) begin
                ipc_data_read_armed <= 1'b0;
                ipc_write_idle <= 16'd0;
                if (ipc_write_idle == 16'hffff) begin
                    ipc_command_bit_count <= 2'd1;
                    ipc_command_shift <= {3'b000, zx8302_wdata[1]};
                end else begin
                    ipc_command_shift <= ipc_command_next;
                    ipc_command_bit_count <= ipc_command_bit_count + 2'd1;
                    if (ipc_command_bit_count == 2'd3) begin
                        ipc_command_bit_count <= 2'd0;
                        if (ipc_command_next == 4'h1) begin
                            ipc_status_command_seen <= 1'b1;
                            ipc_keyboard_response <= 1'b0;
                        end
                        if (ipc_command_next == 4'h8) begin
                            ipc_keyboard_command_seen <= 1'b1;
                            ipc_keyboard_response <= 1'b1;
                            ipc_keyboard_read_count <= 5'd0;
                        end
                    end
                end
            end else if (ipc_write_idle != 16'hffff) begin
                ipc_write_idle <= ipc_write_idle + 16'd1;
            end

            // QDOS polls IPC BUSY with BTST, then performs a separate read
            // of the same byte to consume COMDATA. Count only that final read.
            if (!ipc_command_pulse && zx8302_status_read) begin
                if (ipc_data_read_armed)
                    ipc_data_read_armed <= 1'b0;
                else if (!bus_mem_data[14])
                    ipc_data_read_armed <= 1'b1;
            end

            if (ipc_keyboard_response && ipc_serial_data_read &&
                (ipc_keyboard_read_count != 5'h1f)) begin
                ipc_keyboard_read_count <= ipc_keyboard_read_count + 5'd1;
                if (ipc_keyboard_read_count <= 5'd3)
                    ipc_keyboard_count_shift <= {
                        ipc_keyboard_count_shift[2:0], bus_mem_data[15]
                    };
                if ((ipc_keyboard_read_count == 5'd3) &&
                    !ipc_keyboard_result_latched &&
                    (ipc_keyboard_count_next[2:0] != 3'd0))
                    ipc_keyboard_count <= ipc_keyboard_count_next;
                if ((ipc_keyboard_read_count >= 5'd4) &&
                    (ipc_keyboard_read_count <= 5'd7))
                    ipc_keyboard_modifier_shift <= {
                        ipc_keyboard_modifier_shift[2:0], bus_mem_data[15]
                    };
                if ((ipc_keyboard_read_count == 5'd7) &&
                    !ipc_keyboard_result_latched)
                    ipc_keyboard_modifier <= {
                        ipc_keyboard_modifier_shift[2:0], bus_mem_data[15]
                    };
                if ((ipc_keyboard_read_count >= 5'd8) &&
                    (ipc_keyboard_read_count <= 5'd15))
                    ipc_keyboard_keycode_shift <= {
                        ipc_keyboard_keycode_shift[6:0], bus_mem_data[15]
                    };
                if ((ipc_keyboard_read_count == 5'd15) &&
                    !ipc_keyboard_result_latched) begin
                    ipc_keyboard_keycode <= {
                        ipc_keyboard_keycode_shift[6:0], bus_mem_data[15]
                    };
                    ipc_keyboard_result_latched <= 1'b1;
                    keyboard_diag_collecting <= 1'b0;
                    qdos_monitor_timer <= 25'h1ffffff;
                end
            end

            if (qdos_monitor_timer != 25'd0) begin
                qdos_monitor_timer <= qdos_monitor_timer - 25'd1;
                if (cpu_write_p && !qdos_ascii_write_seen) begin
                    qdos_ascii_write_seen <= 1'b1;
                    qdos_ascii_address <= bus_mem_addr;
                    qdos_ascii_ds <= bus_mem_ds;
                end
                if (cpu_read_p && qdos_ascii_write_seen &&
                    (bus_mem_addr == qdos_ascii_address) &&
                    (bus_mem_ds == qdos_ascii_ds))
                    qdos_ascii_read_seen <= 1'b1;
                if (qdos_ascii_read_seen && cpu_screen_write)
                    qdos_screen_write_seen <= 1'b1;
                if (qdos_monitor_timer == 25'd1)
                    keyboard_diag_timer <= 27'h7ffffff;
            end

            if (keyboard_diag_timer != 27'd0)
                keyboard_diag_timer <= keyboard_diag_timer - 27'd1;

            if (keyboard_diag_collecting) begin
                if (|companion_keyboard_matrix)
                    keyboard_matrix_seen <= 1'b1;
                if (keyboard_diag_collect_timer != 26'd0)
                    keyboard_diag_collect_timer <=
                        keyboard_diag_collect_timer - 26'd1;
                else begin
                    keyboard_diag_collecting <= 1'b0;
                    keyboard_diag_timer <= 27'h7ffffff;
                end
            end

            if (companion_key_press_event) begin
                keyboard_diag_timer <= 27'd0;
                keyboard_diag_collect_timer <= 26'h3ffffff;
                keyboard_diag_collecting <= 1'b1;
                keyboard_matrix_seen <= |companion_keyboard_matrix;
                key_vblank_snapshot <= vblank_ack_count;
                key_ipc_snapshot <= ipc_command_count;
                ipc_status_command_seen <= 1'b0;
                ipc_keyboard_command_seen <= 1'b0;
                ipc_keyboard_response <= 1'b0;
                ipc_keyboard_read_count <= 5'd0;
                ipc_keyboard_keycode_shift <= 8'd0;
                ipc_keyboard_keycode <= 8'd0;
                ipc_keyboard_count_shift <= 4'd0;
                ipc_keyboard_count <= 4'd0;
                ipc_keyboard_modifier_shift <= 4'd0;
                ipc_keyboard_modifier <= 4'd0;
                qdos_monitor_timer <= 25'd0;
                qdos_ascii_write_seen <= 1'b0;
                qdos_ascii_read_seen <= 1'b0;
                qdos_screen_write_seen <= 1'b0;
                qdos_ascii_address <= 22'd0;
                qdos_ascii_ds <= 2'b11;
                ipc_keyboard_result_latched <= 1'b0;
            end
        end
    end

    wire [3:0] keyboard_diag_bits = {
        1'b1,
        keyboard_matrix_seen,
        vblank_ack_count != key_vblank_snapshot,
        ipc_command_count != key_ipc_snapshot
    };
    wire [3:0] qdos_keyboard_bits = {
        ipc_keyboard_count[2:0] != 3'd0,
        qdos_ascii_write_seen,
        qdos_ascii_read_seen,
        qdos_screen_write_seen
    };
    wire [3:0] keyboard_keycode_high = ipc_keyboard_keycode[7:4];
    wire [3:0] keyboard_keycode_low = ipc_keyboard_keycode[3:0];
    wire keyboard_diag_area = (keyboard_diag_timer != 27'd0) &&
                              (x >= 11'd232) && (x < 11'd488) &&
                              (y >= 10'd32) && (y < 10'd352);
    wire [1:0] keyboard_diag_slot = (x - 11'd232) >> 6;
    wire [5:0] keyboard_diag_cell_x = (x - 11'd232) & 11'h03f;
    wire [5:0] keyboard_diag_cell_y = (y - 10'd32) & 10'h03f;
    wire [2:0] keyboard_diag_row = (y - 10'd32) >> 6;
    wire keyboard_diag_border = (keyboard_diag_cell_x < 6'd3) ||
                                (keyboard_diag_cell_x >= 6'd61) ||
                                (keyboard_diag_cell_y < 6'd3) ||
                                (keyboard_diag_cell_y >= 6'd61);
    reg keyboard_diag_value;
    always @(*) begin
        case (keyboard_diag_row)
            3'd0: keyboard_diag_value =
                    qdos_keyboard_bits[3 - keyboard_diag_slot];
            3'd1: keyboard_diag_value =
                    ipc_keyboard_count[3 - keyboard_diag_slot];
            3'd2: keyboard_diag_value =
                    ipc_keyboard_modifier[3 - keyboard_diag_slot];
            3'd3: keyboard_diag_value =
                    keyboard_keycode_high[3 - keyboard_diag_slot];
            default: keyboard_diag_value =
                    keyboard_keycode_low[3 - keyboard_diag_slot];
        endcase
    end
    wire [23:0] keyboard_diag_rgb = keyboard_diag_border ? 24'hffffff :
                                    keyboard_diag_value ? 24'h20e060 :
                                                          24'h000000;

    wire [23:0] hdmi_rgb = dynamic_rom_wait ? companion_diag_rgb :
                           memory_status_area ? memory_status_rgb : rgb;
    wire [23:0] osd_rgb;

    ql_companion_osd companion_osd (
        .clk_bus(clk_pixel),
        .clk_pixel(clk_hdmi),
        .reset(video_reset),
        .data_strobe(mcu_osd_strobe),
        .data_start(mcu_start),
        .data_in(mcu_data),
        .x(x),
        .y(y),
        .rgb_in(hdmi_rgb),
        .rgb_out(osd_rgb)
    );

    nanoql_hdmi #(
        .PIXEL_CLOCK(74_250_000)
    ) hdmi_out (
        .clk_pixel_x5(clk_hdmi_x5),
        .clk_pixel(clk_hdmi),
        .reset(video_reset),
        .rgb(osd_rgb),
        .ql_audio(ql_audio),
        .tmds_clk_n(tmds_clk_n),
        .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n),
        .tmds_d_p(tmds_d_p)
    );

    reg [24:0] heartbeat = 25'd0;
    reg [23:0] keyboard_activity = 24'd0;
    always @(posedge clk_pixel or negedge pll_lock) begin
        if (!pll_lock) begin
            heartbeat <= 25'd0;
            keyboard_activity <= 24'd0;
        end else begin
            heartbeat <= heartbeat + 25'd1;
            if (companion_key_event)
                keyboard_activity <= 24'hffffff;
            else if (keyboard_activity != 24'd0)
                keyboard_activity <= keyboard_activity - 24'd1;
        end
    end

    // Board LEDs are active-low on the Tang Nano 20K.
    assign leds_n[0] = ~heartbeat[24];
    assign leds_n[1] = ~(pll_lock && sdram_init_done &&
                         (rom_is_dynamic ? rom_load_done :
                          rom_is_diagnostic ? cpu_boot_done : zx8302_ipc_ready) &&
                         !memory_failure);
    assign leds_n[2] = ~(fetch_underflow || memory_failure);
    assign leds_n[3] = ~blank_active;
    assign leds_n[4] = ~mode8_active;
    assign leds_n[5] = rom_is_diagnostic ? ~ql_native_frame_div[5] :
                                             ~(|keyboard_activity);

endmodule



