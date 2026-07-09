module ql_video_scanout(
    input  wire        clk,
    input  wire        visible,
    input  wire        ql_area,
    input  wire [8:0]  ql_x,
    input  wire [7:0]  ql_y,
    input  wire        mode8,
    input  wire        blank,
    input  wire        membase,
    input  wire        flash_phase,

    output wire [18:0] addr,
    output wire        rd,
    input  wire [15:0] din,

    output reg  [23:0] rgb
);

    localparam [18:0] QL_SCREEN_BASE_0 = 19'h10000;
    localparam [18:0] QL_SCREEN_BASE_1 = 19'h14000;

    // Both QL display modes use 64 16-bit words per scanline.
    // Mode 4: 512 pixels, 8 pixels per word.
    // Mode 8: 256 pixels, 4 pixels per word, doubled to 512 HDMI pixels here.
    wire [13:0] word_offset = {ql_y, ql_x[8:3]};
    assign addr = (membase ? QL_SCREEN_BASE_1 : QL_SCREEN_BASE_0) + {5'd0, word_offset};
    assign rd = ql_area;

    reg visible_d;
    reg ql_area_d;
    reg mode8_d;
    reg blank_d;
    reg flash_phase_d;
    reg [8:0] ql_x_d;

    wire [2:0] mode4_bit_index = ql_x_d[2:0];
    wire [1:0] mode4_code = {
        din[15 - mode4_bit_index],
        din[7 - mode4_bit_index]
    };

    wire [1:0] mode8_pixel_index = ql_x_d[2:1];
    wire [2:0] mode8_shift = {mode8_pixel_index, 1'b0};
    wire mode8_green = din[15 - mode8_shift];
    wire mode8_flash = din[14 - mode8_shift];
    wire mode8_red   = din[7 - mode8_shift];
    wire mode8_blue  = din[6 - mode8_shift];
    wire [2:0] mode8_code = {mode8_green, mode8_red, mode8_blue};

    function [23:0] ql_mode4_palette;
        input [1:0] code;
        begin
            case (code)
                2'b00: ql_mode4_palette = 24'h000000;
                2'b01: ql_mode4_palette = 24'hd02020;
                2'b10: ql_mode4_palette = 24'h20b040;
                default: ql_mode4_palette = 24'hffffff;
            endcase
        end
    endfunction

    function [23:0] ql_mode8_palette;
        input [2:0] code;
        begin
            case (code)
                3'b000: ql_mode8_palette = 24'h000000;
                3'b001: ql_mode8_palette = 24'h2040d0;
                3'b010: ql_mode8_palette = 24'hd02020;
                3'b011: ql_mode8_palette = 24'hd030d0;
                3'b100: ql_mode8_palette = 24'h20b040;
                3'b101: ql_mode8_palette = 24'h20c0c0;
                3'b110: ql_mode8_palette = 24'he0d040;
                default: ql_mode8_palette = 24'hffffff;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        visible_d <= visible;
        ql_area_d <= ql_area;
        ql_x_d <= ql_x;
        mode8_d <= mode8;
        blank_d <= blank;
        flash_phase_d <= flash_phase;
    end

    always @* begin
        if (!visible_d) begin
            rgb = 24'h000000;
        end else if (!ql_area_d) begin
            rgb = mode8_d ? 24'h202010 : 24'h102040;
        end else if (blank_d) begin
            rgb = 24'h000000;
        end else if (mode8_d) begin
            rgb = (mode8_flash && flash_phase_d) ? 24'hffffff : ql_mode8_palette(mode8_code);
        end else begin
            rgb = ql_mode4_palette(mode4_code);
        end
    end

endmodule


