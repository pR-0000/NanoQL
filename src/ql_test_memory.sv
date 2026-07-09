module ql_test_memory(
    input  wire        clk,
    input  wire [18:0] addr,
    input  wire        rd,
    output reg  [15:0] data
);

    wire screen_base_1 = addr[14];
    wire [13:0] local_addr = addr[13:0];

    function [15:0] mode4_word;
        input [13:0] word_addr;
        integer bit_index;
        reg [7:0] y;
        reg [5:0] word_x;
        reg [8:0] pixel_x;
        reg [1:0] color_code;
        reg [15:0] word_value;
        begin
            y = word_addr[13:6];
            word_x = word_addr[5:0];
            word_value = 16'h0000;

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                pixel_x = {word_x, 3'b000} + bit_index[2:0];

                if ((pixel_x[5:0] == 6'd0) || (y[4:0] == 5'd0))
                    color_code = 2'b11;
                else if (pixel_x[8:1] == y)
                    color_code = 2'b11;
                else if ((pixel_x[8:1] + y) == 8'hff)
                    color_code = 2'b11;
                else if (y < 8'd64)
                    color_code = (pixel_x[4] ^ y[4]) ? 2'b01 : 2'b00;
                else if (y < 8'd128)
                    color_code = (pixel_x[4] ^ y[4]) ? 2'b10 : 2'b00;
                else if (y < 8'd192)
                    color_code = (pixel_x[4] ^ y[4]) ? 2'b11 : 2'b00;
                else
                    color_code = (pixel_x[5] ^ y[5]) ? 2'b10 : 2'b01;

                // ZX8301 mode=0 packing: high byte green plane, low byte red plane.
                word_value[15 - bit_index] = color_code[1];
                word_value[7 - bit_index]  = color_code[0];
            end

            mode4_word = word_value;
        end
    endfunction

    function [15:0] mode8_word;
        input [13:0] word_addr;
        integer pixel_index;
        integer plane_shift;
        reg [7:0] y;
        reg [5:0] word_x;
        reg [7:0] pixel_x;
        reg [2:0] color_code;
        reg flash_bit;
        reg [15:0] word_value;
        begin
            y = word_addr[13:6];
            word_x = word_addr[5:0];
            word_value = 16'h0000;

            for (pixel_index = 0; pixel_index < 4; pixel_index = pixel_index + 1) begin
                pixel_x = {word_x, 2'b00} + pixel_index[1:0];
                flash_bit = 1'b0;

                if ((pixel_x[4:0] == 5'd0) || (y[4:0] == 5'd0)) begin
                    color_code = 3'b111;
                end else if (pixel_x == y) begin
                    color_code = 3'b111;
                end else if ((pixel_x + y) == 8'hff) begin
                    color_code = 3'b111;
                end else if (y < 8'd32) begin
                    color_code = 3'b001;
                end else if (y < 8'd64) begin
                    color_code = 3'b010;
                end else if (y < 8'd96) begin
                    color_code = 3'b011;
                end else if (y < 8'd128) begin
                    color_code = 3'b100;
                end else if (y < 8'd160) begin
                    color_code = 3'b101;
                end else if (y < 8'd192) begin
                    color_code = 3'b110;
                end else if (y < 8'd224) begin
                    color_code = 3'b111;
                end else begin
                    color_code = (pixel_x[4] ^ y[4]) ? 3'b001 : 3'b100;
                    flash_bit = pixel_x[5];
                end

                // ZX8301 mode=1 packing: high byte pairs are G,F; low byte pairs are R,B.
                plane_shift = pixel_index * 2;
                word_value[15 - plane_shift] = color_code[2];
                word_value[14 - plane_shift] = flash_bit;
                word_value[7 - plane_shift]  = color_code[1];
                word_value[6 - plane_shift]  = color_code[0];
            end

            mode8_word = word_value;
        end
    endfunction

    always @(posedge clk) begin
        if (rd)
            data <= screen_base_1 ? mode8_word(local_addr) : mode4_word(local_addr);
        else
            data <= 16'h0000;
    end

endmodule
