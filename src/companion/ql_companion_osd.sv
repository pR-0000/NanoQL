// FPGA Companion u8g2-compatible 128x64 on-screen display.
// Protocol and memory layout are adapted from MiSTeryNano osd_u8g2.v.
// SPDX-License-Identifier: GPL-3.0-or-later
module ql_companion_osd (
    input  wire        clk,
    input  wire        reset,
    input  wire        data_strobe,
    input  wire        data_start,
    input  wire [7:0]  data_in,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);

    localparam [10:0] OSD_X = 11'd232;
    localparam [9:0]  OSD_Y = 10'd224;
    localparam [10:0] OSD_W = 11'd256;
    localparam [9:0]  OSD_H = 10'd128;
    localparam [10:0] BORDER = 11'd4;
    localparam [10:0] SHADOW = 11'd8;

    reg enabled;
    reg [7:0] command;
    reg address_byte;
    reg [9:0] data_address;
    reg [7:0] buffer [0:1023];

    always @(posedge clk) begin
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
    wire [7:0] osd_x_lookahead = osd_x + 8'd1;
    reg [7:0] buffer_byte;

    always @(posedge clk)
        buffer_byte <= buffer[{osd_y[6:4], osd_x_lookahead[7:1]}];

    wire text_pixel = buffer_byte[osd_y[3:1]];
    wire [23:0] dim_rgb = {1'b0, rgb_in[23:17],
                            1'b0, rgb_in[15:9],
                            1'b0, rgb_in[7:1]};
    wire [23:0] shadow_rgb = {2'b00, rgb_in[23:18],
                               2'b00, rgb_in[15:10],
                               2'b00, rgb_in[7:2]};
    wire [23:0] panel_rgb = text_area && text_pixel ? 24'hffffff :
                             panel ? 24'h123c3a : dim_rgb;

    assign rgb_out = !enabled ? rgb_in :
                     panel ? panel_rgb :
                     shadow ? shadow_rgb : rgb_in;

endmodule
