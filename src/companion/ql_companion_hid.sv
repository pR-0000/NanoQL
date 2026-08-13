// USB keyboard events from FPGA Companion to the Sinclair QL matrix.
// Matrix layout and special-key behavior adapted from mist-devel/ql
// keyboard.v, copyright (c) 2015 Till Harbaum, licensed under GPLv3+.
module ql_companion_hid #(
    parameter integer CAPS_PULSE_CYCLES = 1485000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        data_strobe,
    input  wire        data_start,
    input  wire [7:0]  data_in,
    input  wire        host_keyboard_azerty,
    input  wire        rom_keyboard_french,
    output reg  [7:0]  data_out,
    output wire [63:0] matrix,
    output reg         key_event,
    output reg         key_press_event
);

    reg [3:0] state;
    reg [7:0] command;
    reg [63:0] ql_matrix;
    reg [63:0] remote_matrix;
    reg [5:0] modifiers;
    reg [11:1] special;
    reg layout_shift_force;
    reg layout_shift_suppress;
    reg layout_ctrl_force;
    reg layout_ctrl_suppress;
    reg layout_alt_force;
    reg layout_alt_suppress;
    reg usb_caps_lock;
    reg [21:0] caps_pulse_count;
    wire caps_pulse = caps_pulse_count != 22'd0;

    wire shift_down = modifiers[1] || modifiers[4];
    wire ctrl_down = modifiers[0] || modifiers[3];
    wire alt_down = modifiers[2] || modifiers[5];

    function [6:0] translated_usage;
        input [6:0] usage;
        input shifted;
        begin
            translated_usage = usage;
            if (host_keyboard_azerty != rom_keyboard_french) begin
                case (usage)
                    7'h04: translated_usage = 7'h14; // A <-> Q
                    7'h14: translated_usage = 7'h04;
                    7'h1a: translated_usage = 7'h1d; // W <-> Z
                    7'h1d: translated_usage = 7'h1a;
                    default: begin
                        if (host_keyboard_azerty && !rom_keyboard_french) begin
                            if (usage == 7'h20)
                                // AZERTY key 3 is quote without Shift and 3
                                // with Shift. On the English QL hardware,
                                // double quote is the shifted 9 contact.
                                translated_usage = shifted ? 7'h20 : 7'h26;
                            else if (usage == 7'h33)
                                translated_usage = 7'h10; // AZERTY M -> QL M
                            else if (usage == 7'h10)
                                translated_usage = shifted ? 7'h38 : 7'h36;
                            else if (usage == 7'h36)
                                translated_usage = shifted ? 7'h37 : 7'h33;
                            else if (usage == 7'h37)
                                translated_usage = 7'h33; // colon -> Shift+semicolon
                        end else if (!host_keyboard_azerty &&
                                     rom_keyboard_french) begin
                            if (usage == 7'h10)
                                translated_usage = 7'h33; // QWERTY M -> French M
                            else if (usage == 7'h36)
                                translated_usage = 7'h10; // QWERTY comma -> French comma
                            else if (usage == 7'h33)
                                translated_usage = shifted ? 7'h37 : 7'h36;
                        end
                    end
                endcase
            end
        end
    endfunction

    // Decode printable PC keys into characters. Values 0x80..0x87 represent
    // French national characters that are not part of 7-bit ASCII.
    function [8:0] usb_character;
        input [6:0] usage;
        input shifted;
        input ctrl;
        input alt;
        input azerty;
        begin
            usb_character = 9'd0;
            if (azerty) begin
                if (alt) begin
                    case (usage)
                        7'h1f: usb_character = {1'b1, 8'h7e}; // AltGr+2 ~
                        7'h20: usb_character = {1'b1, 8'h23}; // AltGr+3 #
                        7'h21: usb_character = {1'b1, 8'h7b}; // AltGr+4 {
                        7'h22: usb_character = {1'b1, 8'h5b}; // AltGr+5 [
                        7'h23: usb_character = {1'b1, 8'h7c}; // AltGr+6 |
                        7'h25: usb_character = {1'b1, 8'h5c}; // AltGr+8 backslash
                        7'h26: usb_character = {1'b1, 8'h5e}; // AltGr+9 ^
                        7'h27: usb_character = {1'b1, 8'h40}; // AltGr+0 @
                        7'h2d: usb_character = {1'b1, 8'h5d}; // AltGr+) ]
                        7'h2e: usb_character = {1'b1, 8'h7d}; // AltGr+= }
                        default: usb_character = 9'd0;
                    endcase
                end else begin
                    case (usage)
                        7'h1e: usb_character = {1'b1, shifted ? 8'h31 : 8'h26};
                        7'h1f: usb_character = {1'b1, shifted ? 8'h32 : 8'h80}; // e acute
                        7'h20: usb_character = {1'b1, shifted ? 8'h33 : 8'h22};
                        7'h21: usb_character = {1'b1, shifted ? 8'h34 : 8'h27};
                        7'h22: usb_character = {1'b1, shifted ? 8'h35 : 8'h28};
                        7'h23: usb_character = {1'b1, shifted ? 8'h36 : 8'h2d};
                        7'h24: usb_character = {1'b1, shifted ? 8'h37 : 8'h85}; // e grave
                        7'h25: usb_character = {1'b1, shifted ? 8'h38 : 8'h5f};
                        7'h26: usb_character = {1'b1, shifted ? 8'h39 : 8'h86}; // c cedilla
                        7'h27: usb_character = {1'b1, shifted ? 8'h30 : 8'h87}; // a grave
                        7'h2d: usb_character = {1'b1, shifted ? 8'h84 : 8'h29}; // degree
                        7'h2e: usb_character = {1'b1, shifted ? 8'h2b : 8'h3d};
                        7'h2f: usb_character = shifted ? 9'd0 : {1'b1, 8'h5e};
                        7'h30: usb_character = {1'b1, shifted ? 8'h83 : 8'h24}; // pound
                        7'h31: usb_character = shifted ? 9'd0 : {1'b1, 8'h2a};
                        7'h34: usb_character = {1'b1, shifted ? 8'h25 : 8'h82}; // u grave
                        7'h36: usb_character = {1'b1, shifted ? 8'h2e : 8'h3b};
                        7'h37: usb_character = {1'b1, shifted ? 8'h2f : 8'h3a};
                        7'h38: usb_character = {1'b1, shifted ? 8'h81 : 8'h21}; // section
                        7'h64: usb_character = {1'b1, shifted ? 8'h3e : 8'h3c};
                        default: usb_character = 9'd0;
                    endcase
                end
            end else if (!ctrl && !alt) begin
                case (usage)
                    7'h1e: usb_character = {1'b1, shifted ? 8'h21 : 8'h31};
                    7'h1f: usb_character = {1'b1, shifted ? 8'h40 : 8'h32};
                    7'h20: usb_character = {1'b1, shifted ? 8'h23 : 8'h33};
                    7'h21: usb_character = {1'b1, shifted ? 8'h24 : 8'h34};
                    7'h22: usb_character = {1'b1, shifted ? 8'h25 : 8'h35};
                    7'h23: usb_character = {1'b1, shifted ? 8'h5e : 8'h36};
                    7'h24: usb_character = {1'b1, shifted ? 8'h26 : 8'h37};
                    7'h25: usb_character = {1'b1, shifted ? 8'h2a : 8'h38};
                    7'h26: usb_character = {1'b1, shifted ? 8'h28 : 8'h39};
                    7'h27: usb_character = {1'b1, shifted ? 8'h29 : 8'h30};
                    7'h2d: usb_character = {1'b1, shifted ? 8'h5f : 8'h2d};
                    7'h2e: usb_character = {1'b1, shifted ? 8'h2b : 8'h3d};
                    7'h2f: usb_character = {1'b1, shifted ? 8'h7b : 8'h5b};
                    7'h30: usb_character = {1'b1, shifted ? 8'h7d : 8'h5d};
                    7'h31: usb_character = {1'b1, shifted ? 8'h7c : 8'h5c};
                    7'h33: usb_character = {1'b1, shifted ? 8'h3a : 8'h3b};
                    7'h34: usb_character = {1'b1, shifted ? 8'h22 : 8'h27};
                    7'h35: usb_character = {1'b1, shifted ? 8'h7e : 8'h60};
                    7'h36: usb_character = {1'b1, shifted ? 8'h3c : 8'h2c};
                    7'h37: usb_character = {1'b1, shifted ? 8'h3e : 8'h2e};
                    7'h38: usb_character = {1'b1, shifted ? 8'h3f : 8'h2f};
                    7'h64: usb_character = {1'b1, shifted ? 8'h3e : 8'h3c};
                    default: usb_character = 9'd0;
                endcase
            end
        end
    endfunction

    // Return {valid, alt, ctrl, shift, usage}. The usage is the physical QL
    // matrix contact represented by the existing HID-to-matrix table below.
    function [10:0] ql_character_key;
        input [7:0] character;
        input french;
        begin
            ql_character_key = 11'd0;
            case (character)
                "0": ql_character_key = {1'b1, 3'b000, 7'h27};
                "1": ql_character_key = {1'b1, 3'b000, 7'h1e};
                "2": ql_character_key = {1'b1, 3'b000, 7'h1f};
                "3": ql_character_key = {1'b1, 3'b000, 7'h20};
                "4": ql_character_key = {1'b1, 3'b000, 7'h21};
                "5": ql_character_key = {1'b1, 3'b000, 7'h22};
                "6": ql_character_key = {1'b1, 3'b000, 7'h23};
                "7": ql_character_key = {1'b1, 3'b000, 7'h24};
                "8": ql_character_key = {1'b1, 3'b000, 7'h25};
                "9": ql_character_key = {1'b1, 3'b000, 7'h26};
                "!": ql_character_key = {1'b1, 3'b001, 7'h1e};
                "#": ql_character_key = {1'b1, 3'b001, 7'h20};
                "$": ql_character_key = {1'b1, 3'b001, 7'h21};
                "%": ql_character_key = {1'b1, 3'b001, 7'h22};
                "&": ql_character_key = {1'b1, 3'b001, 7'h24};
                "*": ql_character_key = {1'b1, 3'b001, 7'h25};
                "(": ql_character_key = {1'b1, 3'b001, 7'h26};
                ")": ql_character_key = {1'b1, 3'b001, 7'h27};
                "-": ql_character_key = {1'b1, 3'b000, 7'h2d};
                "_": ql_character_key = {1'b1, 3'b001, 7'h2d};
                "=": ql_character_key = {1'b1, 3'b000, 7'h2e};
                "+": ql_character_key = {1'b1, 3'b001, 7'h2e};
                ",": ql_character_key = french ?
                      {1'b1, 3'b000, 7'h10} : {1'b1, 3'b000, 7'h36};
                ".": ql_character_key = french ?
                      {1'b1, 3'b000, 7'h36} : {1'b1, 3'b000, 7'h37};
                ";": ql_character_key = french ?
                      {1'b1, 3'b000, 7'h37} : {1'b1, 3'b000, 7'h33};
                ":": ql_character_key = french ?
                      {1'b1, 3'b001, 7'h37} : {1'b1, 3'b001, 7'h33};
                "'": ql_character_key = french ?
                      {1'b1, 3'b001, 7'h23} : {1'b1, 3'b000, 7'h34};
                8'h22: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h1f} : {1'b1, 3'b001, 7'h34};
                "@": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h23} : {1'b1, 3'b001, 7'h1f};
                "<": ql_character_key = french ?
                      {1'b1, 3'b001, 7'h10} : {1'b1, 3'b001, 7'h36};
                ">": ql_character_key = french ?
                      {1'b1, 3'b001, 7'h36} : {1'b1, 3'b001, 7'h37};
                "[": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h26} : {1'b1, 3'b000, 7'h2f};
                "]": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h27} : {1'b1, 3'b000, 7'h30};
                "{": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h2d} : {1'b1, 3'b001, 7'h2f};
                "}": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h2e} : {1'b1, 3'b001, 7'h30};
                "^": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h32} : {1'b1, 3'b001, 7'h23};
                "`": ql_character_key = french ?
                      {1'b1, 3'b100, 7'h38} : {1'b1, 3'b000, 7'h35};
                8'h5c: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h2f} : {1'b1, 3'b000, 7'h31};
                "|": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h25} : {1'b1, 3'b001, 7'h31};
                "~": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h31} : {1'b1, 3'b001, 7'h35};
                "/": ql_character_key = french ?
                      {1'b1, 3'b001, 7'h34} : {1'b1, 3'b000, 7'h38};
                "?": ql_character_key = {1'b1, 3'b001, 7'h38};
                8'h80: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h2f} : {1'b1, 3'b000, 7'h08};
                8'h81: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h30} : 11'd0;
                8'h82: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h31} : {1'b1, 3'b000, 7'h18};
                8'h83: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h31} : 11'd0;
                8'h84: ql_character_key = french ?
                       {1'b1, 3'b010, 7'h24} : 11'd0;
                8'h85: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h30} : {1'b1, 3'b000, 7'h08};
                8'h86: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h38} : {1'b1, 3'b000, 7'h06};
                8'h87: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h34} : {1'b1, 3'b000, 7'h04};
                default: ql_character_key = 11'd0;
            endcase
        end
    endfunction

    wire azerty_number_caps = host_keyboard_azerty && usb_caps_lock &&
                              (data_in[6:0] >= 7'h1e) &&
                              (data_in[6:0] <= 7'h27);
    wire [8:0] decoded_character = usb_character(
        data_in[6:0], shift_down || azerty_number_caps,
        ctrl_down, alt_down,
        host_keyboard_azerty
    );
    wire [10:0] semantic_key = ql_character_key(
        decoded_character[7:0], rom_keyboard_french
    );

    // Special PC keys become QL modifier combinations. Delay the main key
    // by about 4 ms so the IPC observes the modifier first.
    reg [14:0] delay_div;
    wire delay_tick = (delay_div == 15'h7fff);
    wire [11:1] special_d;

    ql_key_delay delay_1 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[1]),  .delayed(special_d[1]));
    ql_key_delay delay_2 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[2]),  .delayed(special_d[2]));
    ql_key_delay delay_3 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[3]),  .delayed(special_d[3]));
    ql_key_delay delay_4 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[4]),  .delayed(special_d[4]));
    ql_key_delay delay_5 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[5]),  .delayed(special_d[5]));
    ql_key_delay delay_6 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[6]),  .delayed(special_d[6]));
    ql_key_delay delay_7 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[7]),  .delayed(special_d[7]));
    ql_key_delay delay_8 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[8]),  .delayed(special_d[8]));
    ql_key_delay delay_9 (.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[9]),  .delayed(special_d[9]));
    ql_key_delay delay_10(.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[10]), .delayed(special_d[10]));
    ql_key_delay delay_11(.clk(clk), .reset(reset), .tick(delay_tick), .pressed(special[11]), .delayed(special_d[11]));

    wire x_shift = (shift_down && !layout_shift_suppress) ||
                   layout_shift_force || special[3] || special[4] ||
                   special[7] || special[8] || special[9] ||
                   special[10] || special[11];
    wire x_ctrl = (ctrl_down && !layout_ctrl_suppress) ||
                  layout_ctrl_force || special[1] || special[2];
    wire x_alt = (alt_down && !layout_alt_suppress) ||
                 layout_alt_force || special[5] || special[6];
    wire x_left = special_d[1] || special_d[5];
    wire x_right = special_d[2] || special_d[6];
    wire x_up = special_d[3];
    wire x_down = special_d[4];
    wire x_f1 = special_d[7];
    wire x_f2 = special_d[8];
    wire x_f3 = special_d[9];
    wire x_f4 = special_d[10];
    wire x_f5 = special_d[11];

    wire [63:0] generated_matrix = {
        5'b00000, x_alt, x_ctrl, x_shift,
        8'b00000000,
        8'b00000000,
        8'b00000000,
        8'b00000000,
        8'b00000000,
        x_down, 1'b0, 1'b0, x_right, 1'b0, x_up, x_left, 1'b0,
        2'b00, x_f5, x_f3, x_f2, 1'b0, x_f1, x_f4
    };

    // A Caps Lock transition is presented as an isolated QL keypress. This
    // prevents Shift, Ctrl, Alt or another simultaneously held key from
    // changing IPC code E0 into a different matrix combination.
    assign matrix = caps_pulse ? (64'd1 << 25) :
                    (ql_matrix | remote_matrix | generated_matrix);

    always @(posedge clk) begin
        if (reset) begin
            delay_div <= 15'd0;
        end else begin
            delay_div <= delay_tick ? 15'd0 : delay_div + 15'd1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= 4'd0;
            command <= 8'd0;
            data_out <= 8'd0;
            ql_matrix <= 64'd0;
            remote_matrix <= 64'd0;
            modifiers <= 6'd0;
            special <= 11'd0;
            layout_shift_force <= 1'b0;
            layout_shift_suppress <= 1'b0;
            layout_ctrl_force <= 1'b0;
            layout_ctrl_suppress <= 1'b0;
            layout_alt_force <= 1'b0;
            layout_alt_suppress <= 1'b0;
            usb_caps_lock <= 1'b0;
            caps_pulse_count <= 22'd0;
            key_event <= 1'b0;
            key_press_event <= 1'b0;
        end else begin
            if (caps_pulse_count != 22'd0)
                caps_pulse_count <= caps_pulse_count - 22'd1;
            key_event <= 1'b0;
            key_press_event <= 1'b0;
            if (data_strobe) begin
                if (data_start) begin
                    state <= 4'd0;
                    command <= data_in;
                end else begin
                    if (state != 4'd15)
                        state <= state + 4'd1;

                    // HID command 0: protocol version 1.0.
                    if (command == 8'd0) begin
                        if (state == 4'd0)
                            data_out <= 8'h01;
                        if (state == 4'd1)
                            data_out <= 8'h00;
                    end

                    // HID command 1 starts with a raw USB event. Bit 7 is
                    // release and bits 6:0 contain the usage or modifier id.
                    // Command 5 is the NanoQL Link equivalent, already mapped
                    // to the selected QL ROM layout by the host. Keeping the
                    // two paths distinct avoids translating remote keys twice
                    // while preserving physical USB keyboard behavior.
                    if (((command == 8'd1) || (command == 8'd5)) &&
                        (state == 4'd0)) begin
                        key_event <= 1'b1;
                        key_press_event <= !data_in[7];
                        if ((command == 8'd1) && decoded_character[8] &&
                            semantic_key[10]) begin
                            if (data_in[7]) begin
                                layout_shift_force <= 1'b0;
                                layout_shift_suppress <= 1'b0;
                                layout_ctrl_force <= 1'b0;
                                layout_ctrl_suppress <= 1'b0;
                                layout_alt_force <= 1'b0;
                                layout_alt_suppress <= 1'b0;
                            end else begin
                                layout_shift_force <= semantic_key[7] && !shift_down;
                                layout_shift_suppress <= !semantic_key[7] && shift_down;
                                layout_ctrl_force <= semantic_key[8] && !ctrl_down;
                                layout_ctrl_suppress <= !semantic_key[8] && ctrl_down;
                                layout_alt_force <= semantic_key[9] && !alt_down;
                                layout_alt_suppress <= !semantic_key[9] && alt_down;
                            end
                        end
                        case (command == 8'd5 ? data_in[6:0] :
                              ((decoded_character[8] && semantic_key[10]) ?
                               semantic_key[6:0] :
                               translated_usage(data_in[6:0], shift_down)))
                            // A-Z
                            7'h04: ql_matrix[36] <= !data_in[7];
                            7'h05: ql_matrix[20] <= !data_in[7];
                            7'h06: ql_matrix[19] <= !data_in[7];
                            7'h07: ql_matrix[38] <= !data_in[7];
                            7'h08: ql_matrix[52] <= !data_in[7];
                            7'h09: ql_matrix[28] <= !data_in[7];
                            7'h0a: ql_matrix[30] <= !data_in[7];
                            7'h0b: ql_matrix[34] <= !data_in[7];
                            7'h0c: ql_matrix[42] <= !data_in[7];
                            7'h0d: ql_matrix[39] <= !data_in[7];
                            7'h0e: ql_matrix[26] <= !data_in[7];
                            7'h0f: ql_matrix[32] <= !data_in[7];
                            7'h10: ql_matrix[22] <= !data_in[7];
                            7'h11: ql_matrix[62] <= !data_in[7];
                            7'h12: ql_matrix[47] <= !data_in[7];
                            7'h13: ql_matrix[37] <= !data_in[7];
                            7'h14: ql_matrix[51] <= !data_in[7];
                            7'h15: ql_matrix[44] <= !data_in[7];
                            7'h16: ql_matrix[27] <= !data_in[7];
                            7'h17: ql_matrix[54] <= !data_in[7];
                            7'h18: ql_matrix[55] <= !data_in[7];
                            7'h19: ql_matrix[60] <= !data_in[7];
                            7'h1a: ql_matrix[41] <= !data_in[7];
                            7'h1b: ql_matrix[59] <= !data_in[7];
                            7'h1c: ql_matrix[46] <= !data_in[7];
                            7'h1d: ql_matrix[17] <= !data_in[7];

                            // Number row 1-0
                            7'h1e: ql_matrix[35] <= !data_in[7];
                            7'h1f: ql_matrix[49] <= !data_in[7];
                            7'h20: ql_matrix[33] <= !data_in[7];
                            7'h21: ql_matrix[6] <= !data_in[7];
                            7'h22: ql_matrix[2] <= !data_in[7];
                            7'h23: ql_matrix[50] <= !data_in[7];
                            7'h24: ql_matrix[7] <= !data_in[7];
                            7'h25: ql_matrix[48] <= !data_in[7];
                            7'h26: ql_matrix[40] <= !data_in[7];
                            7'h27: ql_matrix[53] <= !data_in[7];

                            // Controls and punctuation
                            7'h28: ql_matrix[8] <= !data_in[7];
                            7'h29: ql_matrix[11] <= !data_in[7];
                            7'h2a: special[1] <= !data_in[7];
                            7'h2b: ql_matrix[43] <= !data_in[7];
                            7'h2c: ql_matrix[14] <= !data_in[7];
                            7'h2d: ql_matrix[45] <= !data_in[7];
                            7'h2e: ql_matrix[29] <= !data_in[7];
                            7'h2f: ql_matrix[24] <= !data_in[7];
                            7'h30: ql_matrix[16] <= !data_in[7];
                            7'h31: ql_matrix[13] <= !data_in[7];
                            7'h32: ql_matrix[21] <= !data_in[7];
                            7'h33: ql_matrix[31] <= !data_in[7];
                            7'h34: ql_matrix[23] <= !data_in[7];
                            7'h36: ql_matrix[63] <= !data_in[7];
                            7'h37: ql_matrix[18] <= !data_in[7];
                            7'h38: ql_matrix[61] <= !data_in[7];
                            // Physical USB Caps Lock is driven by the
                            // authoritative command-8 snapshot below. The
                            // raw event is ignored to avoid double toggles if
                            // either SPI transaction has to be recovered.
                            7'h39: if (command != 8'd1)
                                ql_matrix[25] <= !data_in[7];

                            // F1-F10
                            7'h3a: ql_matrix[1] <= !data_in[7];
                            7'h3b: ql_matrix[3] <= !data_in[7];
                            7'h3c: ql_matrix[4] <= !data_in[7];
                            7'h3d: ql_matrix[0] <= !data_in[7];
                            7'h3e: ql_matrix[5] <= !data_in[7];
                            7'h3f: special[7] <= !data_in[7];
                            7'h40: special[8] <= !data_in[7];
                            7'h41: special[9] <= !data_in[7];
                            7'h42: special[10] <= !data_in[7];
                            7'h43: special[11] <= !data_in[7];

                            // Navigation
                            7'h4a: special[5] <= !data_in[7];
                            7'h4b: special[3] <= !data_in[7];
                            7'h4c: special[2] <= !data_in[7];
                            7'h4d: special[6] <= !data_in[7];
                            7'h4e: special[4] <= !data_in[7];
                            7'h4f: ql_matrix[12] <= !data_in[7];
                            7'h50: ql_matrix[9] <= !data_in[7];
                            7'h51: ql_matrix[15] <= !data_in[7];
                            7'h52: ql_matrix[10] <= !data_in[7];

                            // Companion encodes USB modifier bits as 0x68-0x6f.
                            7'h68: modifiers[0] <= !data_in[7];
                            7'h69: modifiers[1] <= !data_in[7];
                            7'h6a: modifiers[2] <= !data_in[7];
                            7'h6c: modifiers[3] <= !data_in[7];
                            7'h6d: modifiers[4] <= !data_in[7];
                            7'h6e: modifiers[5] <= !data_in[7];
                            7'h64: ql_matrix[21] <= !data_in[7];
                            default: ;
                        endcase
                    end

                    // HID command 6 is reserved for NanoQL Link. Its event
                    // byte addresses a QL matrix contact directly: bit 7 is
                    // release and bits 5:0 select one of the 64 contacts.
                    // It has separate state from command 1, so a remote key
                    // cannot alter or release a key held on the USB keyboard.
                    if ((command == 8'd6) && (state == 4'd0)) begin
                        key_event <= 1'b1;
                        key_press_event <= !data_in[7];
                        remote_matrix[data_in[5:0]] <= !data_in[7];
                    end

                    // Command 7 is an atomic idle snapshot from the physical
                    // USB keyboard. It repairs any event lost between the
                    // BL616 and FPGA without altering NanoQL Link keys.
                    if ((command == 8'd7) && (state == 4'd0)) begin
                        ql_matrix <= 64'd0;
                        modifiers <= 6'd0;
                        special <= 11'd0;
                        layout_shift_force <= 1'b0;
                        layout_shift_suppress <= 1'b0;
                        layout_ctrl_force <= 1'b0;
                        layout_ctrl_suppress <= 1'b0;
                        layout_alt_force <= 1'b0;
                        layout_alt_suppress <= 1'b0;
                        if (usb_caps_lock != data_in[1]) begin
                            usb_caps_lock <= data_in[1];
                            caps_pulse_count <= CAPS_PULSE_CYCLES;
                        end
                    end

                    // Command 8 updates only the authoritative physical USB
                    // Caps Lock state. Unlike command 7 it never clears held
                    // keys or modifiers. The fixed isolated pulse cannot be
                    // converted into Shift+Caps by report ordering.
                    if ((command == 8'd8) && (state == 4'd0) &&
                        (usb_caps_lock != data_in[1])) begin
                        usb_caps_lock <= data_in[1];
                        caps_pulse_count <= CAPS_PULSE_CYCLES;
                    end
                end
            end
        end
    end

endmodule

module ql_key_delay (
    input  wire clk,
    input  wire reset,
    input  wire tick,
    input  wire pressed,
    output wire delayed
);
    reg [3:0] delay;
    assign delayed = &delay;

    always @(posedge clk) begin
        if (reset || !pressed)
            delay <= 4'd0;
        else if (tick)
            delay <= {delay[2:0], 1'b1};
    end
endmodule
