module ql_video_test(
    input  wire        clk_pixel,
    input  wire        reset,
    output wire [18:0] mem_addr,
    output wire        mem_rd,
    input  wire        mem_ready,
    input  wire        mem_data_valid,
    input  wire [15:0] mem_data,
    output wire [23:0] rgb,
    output reg         frame_pulse,
    output wire        mode8_active,
    output wire        blank_active,
    output wire        fetch_underflow,
    output reg  [10:0] x,
    output reg  [9:0]  y
);

    // HDMI PAL standard mode from the MiSTeryNano HDMI core:
    // visible area 720x576, total frame 1024x626, pixel clock 32 MHz.
    localparam [10:0] FRAME_W = 11'd1024;
    localparam [9:0]  FRAME_H = 10'd626;

    wire visible_now;
    wire ql_area_now;
    wire ql_fetch_start_now;
    wire [7:0] ql_fetch_y_now;
    wire [8:0] ql_x_now;
    wire [7:0] ql_y_now;

    ql_hdmi_window hdmi_window (
        .x(x),
        .y(y),
        .visible(visible_now),
        .ql_area(ql_area_now),
        .ql_fetch_start(ql_fetch_start_now),
        .ql_fetch_y(ql_fetch_y_now),
        .ql_x(ql_x_now),
        .ql_y(ql_y_now)
    );

    reg flash_phase;
    reg [5:0] flash_count;
    reg [7:0] frame_count;
    reg zx_cpu_cs;
    reg [7:0] zx_cpu_data;

    wire next_mode8 = frame_count[7];
    wire blank_test = (frame_count[6:2] == 5'd0);

    always @(posedge clk_pixel) begin
        if (reset) begin
            x <= 11'd0;
            y <= 10'd0;
            frame_pulse <= 1'b0;
            frame_count <= 8'd0;
            flash_phase <= 1'b0;
            flash_count <= 6'd0;
            zx_cpu_cs <= 1'b1;
            zx_cpu_data <= 8'h00;
        end else begin
            frame_pulse <= 1'b0;
            zx_cpu_cs <= 1'b0;

            if (x == FRAME_W - 1'b1) begin
                x <= 11'd0;
                if (y == FRAME_H - 1'b1) begin
                    y <= 10'd0;
                    frame_pulse <= 1'b1;
                    frame_count <= frame_count + 8'd1;

                    // Exercise the ZX8301-style control register once per frame.
                    // bit 7 selects screen base, bit 3 selects mode 8, bit 1 blanks.
                    zx_cpu_cs <= 1'b1;
                    zx_cpu_data <= {next_mode8, 3'b000, next_mode8, 1'b0, blank_test, 1'b0};

                    // Match the original core: toggle the mode 8 flash phase
                    // after 26 video frames, independently of the test mode timer.
                    if (flash_count == 6'd25) begin
                        flash_count <= 6'd0;
                        flash_phase <= ~flash_phase;
                    end else begin
                        flash_count <= flash_count + 6'd1;
                    end
                end else begin
                    y <= y + 10'd1;
                end
            end else begin
                x <= x + 11'd1;
            end
        end
    end

    wire video_membase;

    ql_zx8301_lite zx8301_lite (
        .reset(reset),
        .clk_pixel(clk_pixel),
        .clk_bus(clk_pixel),
        .cpu_cs(zx_cpu_cs),
        .cpu_data(zx_cpu_data),
        .visible(visible_now),
        .ql_area(ql_area_now),
        .ql_fetch_start(ql_fetch_start_now),
        .ql_fetch_y(ql_fetch_y_now),
        .ql_x(ql_x_now),
        .ql_y(ql_y_now),
        .flash_phase(flash_phase),
        .addr(mem_addr),
        .rd(mem_rd),
        .rd_ready(mem_ready),
        .din_valid(mem_data_valid),
        .din(mem_data),
        .fetch_underflow(fetch_underflow),
        .mode8(mode8_active),
        .blank(blank_active),
        .membase(video_membase),
        .rgb(rgb)
    );

endmodule
