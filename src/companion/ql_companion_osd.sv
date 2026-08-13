// FPGA Companion u8g2-compatible 128x64 on-screen display.
// Protocol and memory layout are adapted from MiSTeryNano osd_u8g2.v.
// SPDX-License-Identifier: GPL-3.0-or-later
module ql_companion_osd (
    input  wire        clk_bus,
    input  wire        clk_pixel,
    input  wire        reset,
    input  wire        data_strobe,
    input  wire        data_start,
    input  wire [7:0]  data_in,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);

    localparam [10:0] OSD_X = 11'd512;
    localparam [9:0]  OSD_Y = 10'd296;
    localparam [10:0] OSD_W = 11'd256;
    localparam [9:0]  OSD_H = 10'd128;
    localparam [10:0] BORDER = 11'd6;
    localparam [10:0] SHADOW = 11'd8;

    reg enabled;
    reg [7:0] command;
    reg address_byte;
    reg [9:0] data_address;
    reg [7:0] buffer [0:1023];

    always @(posedge clk_bus) begin
        if (reset) begin
            enabled <= 1'b0;
            command <= 8'd0;
            address_byte <= 1'b0;
            data_address <= 10'd0;
        end else if (data_strobe) begin
            if (data_start) begin
                command <= data_in;
                address_byte <= 1'b1;
                data_address <= 10'd0;
            end else begin
                address_byte <= 1'b0;

                if ((command == 8'd1) && address_byte)
                    enabled <= data_in[0];

                if (command == 8'd2) begin
                    if (address_byte) begin
                        data_address <= {data_in[6:0], 3'b000};
                    end else begin
                        buffer[data_address] <= data_in;
                        data_address <= data_address + 10'd1;
                    end
                end
            end
        end
    end

    wire panel = (x >= OSD_X - BORDER) &&
                 (x < OSD_X + OSD_W + BORDER) &&
                 (y >= OSD_Y - BORDER) &&
                 (y < OSD_Y + OSD_H + BORDER);
    wire text_area = (x >= OSD_X) && (x < OSD_X + OSD_W) &&
                     (y >= OSD_Y) && (y < OSD_Y + OSD_H);
    wire shadow = (x >= OSD_X - BORDER + SHADOW) &&
                  (x < OSD_X + OSD_W + BORDER + SHADOW) &&
                  (y >= OSD_Y - BORDER + SHADOW) &&
                  (y < OSD_Y + OSD_H + BORDER + SHADOW);

    wire [7:0] osd_x = x - OSD_X;
    wire [6:0] osd_y = y - OSD_Y;
    reg [7:0] buffer_byte;

    // The buffer and all geometry flags are delayed by the same pixel clock.
    // Reading the current address keeps the highlighted final column inside
    // the panel; the former look-ahead shifted it over the right edge.
    always @(posedge clk_pixel)
        buffer_byte <= buffer[{osd_y[6:4], osd_x[7:1]}];

    reg panel_d;
    reg text_area_d;
    reg shadow_d;
    reg [2:0] osd_y_d;
    reg [23:0] rgb_in_d;

    always @(posedge clk_pixel) begin
        if (reset) begin
            panel_d <= 1'b0;
            text_area_d <= 1'b0;
            shadow_d <= 1'b0;
            osd_y_d <= 3'd0;
            rgb_in_d <= 24'd0;
        end else begin
            panel_d <= panel;
            text_area_d <= text_area;
            shadow_d <= shadow;
            osd_y_d <= osd_y[3:1];
            rgb_in_d <= rgb_in;
        end
    end

    wire text_pixel = buffer_byte[osd_y_d];
    wire [23:0] dim_rgb = {1'b0, rgb_in_d[23:17],
                            1'b0, rgb_in_d[15:9],
                            1'b0, rgb_in_d[7:1]};
    wire [23:0] shadow_rgb = {2'b00, rgb_in_d[23:18],
                               2'b00, rgb_in_d[15:10],
                               2'b00, rgb_in_d[7:2]};
    wire [23:0] panel_rgb = text_area_d ?
                             (text_pixel ? 24'hf4f7f5 : 24'h13272a) :
                             24'h2fb6a3;

    assign rgb_out = !enabled ? rgb_in_d :
                     panel_d ? panel_rgb :
                     shadow_d ? shadow_rgb : dim_rgb;

endmodule
