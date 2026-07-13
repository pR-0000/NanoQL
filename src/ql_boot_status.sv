module ql_boot_status (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [3:0]  status,
    input  wire [7:0]  progress,
    output wire [23:0] rgb
);

    localparam [3:0] STATUS_MEMORY      = 4'd0;
    localparam [3:0] STATUS_WAIT        = 4'd1;
    localparam [3:0] STATUS_BL616       = 4'd2;
    localparam [3:0] STATUS_ROM_MISSING = 4'd3;
    localparam [3:0] STATUS_LOADING     = 4'd4;
    localparam [3:0] STATUS_ROM_FAILED  = 4'd5;
    localparam [3:0] STATUS_RESET_HELD  = 4'd6;
    localparam [3:0] STATUS_SDRAM_FAIL  = 4'd7;

    function automatic [7:0] message_char;
        input [3:0] message_status;
        input [2:0] line;
        input [4:0] column;
        reg [255:0] text;
        begin
            text = {32{8'h20}};
            if (line == 3'd0) begin
                text = {"NANOQL STARTUP", {18{8'h20}}};
            end else begin
                case (message_status)
                    STATUS_MEMORY: begin
                        if (line == 3'd1)
                            text = {"INITIALIZING SDRAM", {14{8'h20}}};
                        else if (line == 3'd2)
                            text = {"PLEASE WAIT", {21{8'h20}}};
                    end
                    STATUS_WAIT: begin
                        if (line == 3'd1)
                            text = {"WAITING FOR BL616", {15{8'h20}}};
                        else if (line == 3'd2)
                            text = {"AUTOMATIC RETRY ACTIVE", {10{8'h20}}};
                    end
                    STATUS_BL616: begin
                        if (line == 3'd1)
                            text = {"BL616 COMPANION NOT READY", {7{8'h20}}};
                        else if (line == 3'd2)
                            text = {"SELECT NORMAL MODE", {14{8'h20}}};
                        else if (line == 3'd3)
                            text = {"DISCONNECT PC DATA USB", {10{8'h20}}};
                    end
                    STATUS_ROM_MISSING: begin
                        if (line == 3'd1)
                            text = {"QL.ROM NOT MOUNTED", {14{8'h20}}};
                        else if (line == 3'd2)
                            text = {"CHECK MICROSD AND FILE", {10{8'h20}}};
                        else if (line == 3'd3)
                            text = {"AUTOMATIC RETRY ACTIVE", {10{8'h20}}};
                    end
                    STATUS_LOADING: begin
                        if (line == 3'd1)
                            text = {"LOADING QL.ROM", {18{8'h20}}};
                    end
                    STATUS_ROM_FAILED: begin
                        if (line == 3'd1)
                            text = {"ROM LOAD OR VERIFY FAILED", {7{8'h20}}};
                        else if (line == 3'd2)
                            text = {"USE A 48 OR 64 KIB ROM", {10{8'h20}}};
                    end
                    STATUS_RESET_HELD: begin
                        if (line == 3'd1)
                            text = {"BL616 IS HOLDING RESET", {10{8'h20}}};
                        else if (line == 3'd2)
                            text = {"SELECT NORMAL MODE", {14{8'h20}}};
                    end
                    default: begin
                        if (line == 3'd1)
                            text = {"SDRAM TEST FAILED", {15{8'h20}}};
                        else if (line == 3'd2)
                            text = {"POWER CYCLE THE BOARD", {11{8'h20}}};
                    end
                endcase
            end
            message_char = text[255 - (column * 8) -: 8];
        end
    endfunction

    function automatic [34:0] glyph;
        input [7:0] character;
        begin
            case (character)
                "A": glyph = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C": glyph = {5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D": glyph = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G": glyph = {5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "H": glyph = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
                "J": glyph = {5'b00111,5'b00010,5'b00010,5'b00010,5'b10010,5'b10010,5'b01100};
                "K": glyph = {5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L": glyph = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": glyph = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": glyph = {5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": glyph = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "Q": glyph = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
                "R": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": glyph = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V": glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W": glyph = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "X": glyph = {5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Y": glyph = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "Z": glyph = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                "0": glyph = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1": glyph = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2": glyph = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3": glyph = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4": glyph = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6": glyph = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7": glyph = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8": glyph = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9": glyph = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                ".": glyph = {5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110};
                default: glyph = 35'd0;
            endcase
        end
    endfunction

    wire text_area = (x >= 11'd104) && (x < 11'd616) &&
                     (y >= 10'd176) && (y < 10'd240);
    wire [8:0] text_x = x - 11'd104;
    wire [5:0] text_y = y - 10'd176;
    wire [4:0] column = text_x[8:4];
    wire [2:0] line = text_y[5:4];
    wire [2:0] glyph_x = text_x[3:1];
    wire [2:0] glyph_y = text_y[3:1];
    wire [7:0] character = message_char(status, line, column);
    wire [34:0] glyph_bits = glyph(character);
    wire text_pixel = text_area && (glyph_x < 3'd5) &&
                      (glyph_y < 3'd7) &&
                      glyph_bits[34 - (glyph_y * 5 + glyph_x)];

    wire progress_border = (status == STATUS_LOADING) &&
                           (x >= 11'd104) && (x < 11'd616) &&
                           (y >= 10'd272) && (y < 10'd296) &&
                           ((x < 11'd108) || (x >= 11'd612) ||
                            (y < 10'd276) || (y >= 10'd292));
    wire progress_fill = (status == STATUS_LOADING) &&
                         (x >= 11'd108) &&
                         (x < 11'd108 + {progress[6:0], 2'b00}) &&
                         (y >= 10'd276) && (y < 10'd292);
    wire error_status = (status == STATUS_ROM_FAILED) ||
                        (status == STATUS_SDRAM_FAIL);
    wire [23:0] text_color = error_status ? 24'hff6058 :
                              (status == STATUS_LOADING) ? 24'h40d8d0 :
                                                           24'hffffff;

    assign rgb = text_pixel ? text_color :
                 progress_border ? 24'hffffff :
                 progress_fill ? 24'h40d8d0 : 24'h061211;

endmodule
