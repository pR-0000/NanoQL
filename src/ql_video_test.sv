module ql_video_test(
    input  wire        clk_pixel,
    input  wire        reset,
    output wire [23:0] rgb,
    output reg         frame_pulse,
    output wire        mode8_active,
    output wire        blank_active,
    output reg  [10:0] x,
    output reg  [9:0]  y
);

    // HDMI PAL standard mode from the MiSTeryNano HDMI core:
    // visible area 720x576, total frame 1024x626, pixel clock 32 MHz.
    localparam [10:0] FRAME_W = 11'd1024;
    localparam [9:0]  FRAME_H = 10'd626;

    wire visible_now;
    wire ql_area_now;
    wire [8:0] ql_x_now;
    wire [7:0] ql_y_now;

    ql_hdmi_window hdmi_window (
        .x(x),
        .y(y),
        .visible(visible_now),
        .ql_area(ql_area_now),
        .ql_x(ql_x_now),
        .ql_y(ql_y_now)
    );

    reg flash_phase;
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

                    if (frame_count == 8'd24)
                        flash_phase <= ~flash_phase;
                end else begin
                    y <= y + 10'd1;
                end
            end else begin
                x <= x + 11'd1;
            end
        end
    end

    wire [18:0] video_addr;
    wire video_rd;
    wire [15:0] video_din;
    wire video_membase;

    ql_test_memory test_memory (
        .clk(clk_pixel),
        .addr(video_addr),
        .rd(video_rd),
        .data(video_din)
    );

    ql_zx8301_lite zx8301_lite (
        .reset(reset),
        .clk_pixel(clk_pixel),
        .clk_bus(clk_pixel),
        .cpu_cs(zx_cpu_cs),
        .cpu_data(zx_cpu_data),
        .visible(visible_now),
        .ql_area(ql_area_now),
        .ql_x(ql_x_now),
        .ql_y(ql_y_now),
        .flash_phase(flash_phase),
        .addr(video_addr),
        .rd(video_rd),
        .din(video_din),
        .mode8(mode8_active),
        .blank(blank_active),
        .membase(video_membase),
        .rgb(rgb)
    );

endmodule
