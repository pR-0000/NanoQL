`timescale 1ns/1ps

module ql_video_scanout(
    input wire reset,
    input wire clk_bus,
    input wire clk_pixel,
    input wire visible,
    input wire ql_area,
    input wire ql_fetch_start,
    input wire [7:0] ql_fetch_y,
    input wire [8:0] ql_x,
    input wire [7:0] ql_y,
    input wire mode8,
    input wire blank,
    input wire [21:0] frame_base,
    input wire frame_buffer_select,
    input wire flash_phase,
    output wire [21:0] addr,
    output wire rd,
    input wire rd_ready,
    input wire din_valid,
    input wire [15:0] din,
    output wire fetch_underflow,
    output wire scanout_buffer_select,
    output wire [23:0] rgb
);
    assign addr = 22'd0;
    assign rd = 1'b0;
    assign fetch_underflow = 1'b0;
    assign scanout_buffer_select = frame_buffer_select;
    assign rgb = 24'd0;
endmodule

module tb_ql_zx8301;
    reg clk_bus = 1'b0;
    reg clk_pixel = 1'b0;
    reg reset = 1'b1;
    reg core_reset = 1'b1;
    reg cpu_cs = 1'b0;
    reg [7:0] cpu_data = 8'd0;

    wire mode8;
    wire blank;
    wire membase;
    wire ntsc;
    wire native_ce;
    wire [9:0] native_h;
    wire [9:0] native_v;
    wire native_hs;
    wire native_vs;
    wire native_hblank;
    wire native_vblank;
    wire native_frame;

    always #5 clk_bus = ~clk_bus;
    always #3 clk_pixel = ~clk_pixel;

    ql_zx8301 #(
        .NATIVE_CE_STEP(32'hffffffff)
    ) dut (
        .reset(reset),
        .core_reset(core_reset),
        .clk_pixel(clk_pixel),
        .clk_bus(clk_bus),
        .cpu_cs(cpu_cs),
        .cpu_data(cpu_data),
        .visible(1'b0),
        .ql_area(1'b0),
        .ql_fetch_start(1'b0),
        .ql_fetch_y(8'd0),
        .ql_x(9'd0),
        .ql_y(8'd0),
        .frame_base(22'h010000),
        .frame_buffer_select(1'b0),
        .addr(),
        .rd(),
        .rd_ready(1'b0),
        .din_valid(1'b0),
        .din(16'd0),
        .fetch_underflow(),
        .mode8(mode8),
        .blank(blank),
        .membase(membase),
        .ntsc(ntsc),
        .rgb(),
        .native_ce(native_ce),
        .native_h(native_h),
        .native_v(native_v),
        .native_hs(native_hs),
        .native_vs(native_vs),
        .native_hblank(native_hblank),
        .native_vblank(native_vblank),
        .native_frame(native_frame)
    );

    task write_mc_stat;
        input [7:0] value;
        begin
            cpu_data = value;
            cpu_cs = 1'b1;
            @(negedge clk_bus);
            #1;
            cpu_cs = 1'b0;
        end
    endtask

    task wait_frame;
        begin : wait_frame_block
            forever begin
                @(posedge clk_bus);
                #1;
                if (native_frame)
                    disable wait_frame_block;
            end
        end
    endtask

    task check_frame;
        input integer expected_ticks;
        input integer expected_lines;
        input integer expected_vblank_lines;
        input integer expected_vsync_lines;
        input integer expected_hblank_ticks;
        integer ticks;
        integer lines;
        integer vblank_lines;
        integer vsync_lines;
        integer hblank_ticks;
        integer max_h;
        integer max_v;
        begin : check_frame_block
            ticks = 0;
            lines = 0;
            vblank_lines = 0;
            vsync_lines = 0;
            hblank_ticks = 0;
            max_h = 0;
            max_v = 0;

            forever begin
                @(posedge clk_bus);
                #1;
                if (native_ce) begin
                    ticks = ticks + 1;
                    if (native_h > max_h)
                        max_h = native_h;
                    if (native_v > max_v)
                        max_v = native_v;
                    if (native_hblank)
                        hblank_ticks = hblank_ticks + 1;

                    // Blanking registers are updated from h=0 to h=1.
                    if (native_h == 10'd1) begin
                        lines = lines + 1;
                        if (native_vblank)
                            vblank_lines = vblank_lines + 1;
                        if (native_vs)
                            vsync_lines = vsync_lines + 1;
                    end
                end

                if (native_frame) begin
                    if (ticks != expected_ticks) begin
                        $display("FAIL: frame ticks %0d, expected %0d",
                                 ticks, expected_ticks);
                        $fatal;
                    end
                    if (lines != expected_lines) begin
                        $display("FAIL: frame lines %0d, expected %0d",
                                 lines, expected_lines);
                        $fatal;
                    end
                    if (vblank_lines != expected_vblank_lines) begin
                        $display("FAIL: VBL lines %0d, expected %0d",
                                 vblank_lines, expected_vblank_lines);
                        $fatal;
                    end
                    if (vsync_lines != expected_vsync_lines) begin
                        $display("FAIL: VSYNC lines %0d, expected %0d",
                                 vsync_lines, expected_vsync_lines);
                        $fatal;
                    end
                    if (hblank_ticks != expected_hblank_ticks) begin
                        $display("FAIL: HBL ticks %0d, expected %0d",
                                 hblank_ticks, expected_hblank_ticks);
                        $fatal;
                    end
                    disable check_frame_block;
                end
            end
        end
    endtask

    reg flash_before;

    initial begin
        repeat (8) @(posedge clk_bus);
        reset = 1'b0;
        repeat (2) @(negedge clk_bus);
        core_reset = 1'b0;

        write_mc_stat(8'h8a);
        if (!membase || !mode8 || !blank || ntsc) begin
            $display("FAIL: MC_STAT PAL control bits");
            $fatal;
        end

        wait_frame();
        check_frame(672 * 312, 312, 56, 6, 160 * 312);

        // Force the next VSYNC to exercise the 26-frame flash divider without
        // making the test simulate another 25 complete frames.
        @(negedge clk_bus);
        dut.flash_count = 6'd25;
        flash_before = dut.flash_phase;
        begin : wait_flash_toggle
            forever begin
                @(posedge clk_bus);
                #1;
                if (dut.flash_phase != flash_before)
                    disable wait_flash_toggle;
            end
        end

        write_mc_stat(8'hca);
        if (!membase || !mode8 || !blank || !ntsc) begin
            $display("FAIL: MC_STAT NTSC control bits");
            $fatal;
        end

        // Discard the mixed PAL/NTSC frame in which MC_STAT changed.
        wait_frame();
        check_frame(664 * 262, 262, 6, 2, 152 * 262);

        core_reset = 1'b1;
        repeat (2) @(negedge clk_bus);
        if (membase || mode8 || blank || ntsc) begin
            $display("FAIL: MC_STAT did not clear on core reset");
            $fatal;
        end

        $display("PASS: ZX8301 MC_STAT, PAL/NTSC raster, VBL/VSYNC, and flash timing");
        $finish;
    end

endmodule
