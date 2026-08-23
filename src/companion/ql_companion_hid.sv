// USB keyboard events from FPGA Companion to the Sinclair QL matrix.
// Matrix layout and special-key behavior adapted from mist-devel/ql
// keyboard.v, copyright (c) 2015 Till Harbaum, licensed under GPLv3+.
module ql_companion_hid #(
    parameter integer KEY_MIN_HOLD_TICKS = 46,
    parameter integer KEY_MOD_DELAY_TICKS = 32
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
    output reg         key_press_event,
    output wire        caps_lock_active
);

    reg [3:0] state;
    reg [7:0] command;
    reg [63:0] ql_matrix;
    reg [63:0] remote_matrix;
    reg [5:0] modifiers;
    reg [11:1] special;
    reg [5:0] semantic_valid;
    reg [6:0] semantic_raw [0:5];
    reg [5:0] semantic_contact [0:5];
    reg [2:0] semantic_mods [0:5];
    localparam integer KEY_TOTAL_HOLD_TICKS =
        KEY_MIN_HOLD_TICKS + KEY_MOD_DELAY_TICKS;
    reg [6:0] semantic_hold [0:5];
    reg [5:0] semantic_release_pending;
    reg usb_caps_lock;
    assign caps_lock_active = usb_caps_lock;

    wire shift_down = modifiers[1] || modifiers[4];
    wire ctrl_down = modifiers[0] || modifiers[3];
    wire alt_down = modifiers[2] || modifiers[5];

    function [5:0] usage_contact;
        input [6:0] usage;
        begin
            usage_contact = 6'd0;
            case (usage)
                7'h04: usage_contact = 6'd36;
                7'h05: usage_contact = 6'd20;
                7'h06: usage_contact = 6'd19;
                7'h07: usage_contact = 6'd38;
                7'h08: usage_contact = 6'd52;
                7'h09: usage_contact = 6'd28;
                7'h0a: usage_contact = 6'd30;
                7'h0b: usage_contact = 6'd34;
                7'h0c: usage_contact = 6'd42;
                7'h0d: usage_contact = 6'd39;
                7'h0e: usage_contact = 6'd26;
                7'h0f: usage_contact = 6'd32;
                7'h10: usage_contact = 6'd22;
                7'h11: usage_contact = 6'd62;
                7'h12: usage_contact = 6'd47;
                7'h13: usage_contact = 6'd37;
                7'h14: usage_contact = 6'd51;
                7'h15: usage_contact = 6'd44;
                7'h16: usage_contact = 6'd27;
                7'h17: usage_contact = 6'd54;
                7'h18: usage_contact = 6'd55;
                7'h19: usage_contact = 6'd60;
                7'h1a: usage_contact = 6'd41;
                7'h1b: usage_contact = 6'd59;
                7'h1c: usage_contact = 6'd46;
                7'h1d: usage_contact = 6'd17;
                7'h1e: usage_contact = 6'd35;
                7'h1f: usage_contact = 6'd49;
                7'h20: usage_contact = 6'd33;
                7'h21: usage_contact = 6'd6;
                7'h22: usage_contact = 6'd2;
                7'h23: usage_contact = 6'd50;
                7'h24: usage_contact = 6'd7;
                7'h25: usage_contact = 6'd48;
                7'h26: usage_contact = 6'd40;
                7'h27: usage_contact = 6'd53;
                7'h2d: usage_contact = 6'd45;
                7'h2e: usage_contact = 6'd29;
                7'h2f: usage_contact = 6'd24;
                7'h30: usage_contact = 6'd16;
                7'h31: usage_contact = 6'd13;
                7'h32: usage_contact = 6'd21;
                7'h33: usage_contact = 6'd31;
                7'h34: usage_contact = 6'd23;
                7'h36: usage_contact = 6'd63;
                7'h37: usage_contact = 6'd18;
                7'h38: usage_contact = 6'd61;
                7'h64: usage_contact = 6'd21;
                default: ;
            endcase
        end
    endfunction

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

    // Decode printable PC keys into QL character codes. The QL's 8-bit set
    // differs from ASCII above 0x5f; national characters therefore use their
    // actual QL codes here instead of private placeholders.
    function [8:0] usb_character;
        input [6:0] usage;
        input shifted;
        input ctrl;
        input alt;
        input azerty;
        input caps;
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
                        7'h24: usb_character = {1'b1, 8'h9f}; // AltGr+7 `
                        7'h25: usb_character = {1'b1, 8'h5c}; // AltGr+8 backslash
                        7'h26: usb_character = {1'b1, 8'h5e}; // AltGr+9 ^
                        7'h27: usb_character = {1'b1, 8'h40}; // AltGr+0 @
                        7'h2d: usb_character = {1'b1, 8'h5d}; // AltGr+) ]
                        7'h2e: usb_character = {1'b1, 8'h7d}; // AltGr+= }
                        default: usb_character = 9'd0;
                    endcase
                end else if (!ctrl) begin
                    case (usage)
                        7'h10: usb_character = {1'b1, shifted ? "?" : ","};
                        7'h1e: usb_character = {1'b1, shifted ? 8'h31 : 8'h26};
                        7'h1f: usb_character = {1'b1, shifted ? 8'h32 :
                                               (caps ? 8'ha3 : 8'h83)}; // e acute
                        7'h20: usb_character = {1'b1, shifted ? 8'h33 : 8'h22};
                        7'h21: usb_character = {1'b1, shifted ? 8'h34 : 8'h27};
                        7'h22: usb_character = {1'b1, shifted ? 8'h35 : 8'h28};
                        7'h23: usb_character = {1'b1, shifted ? 8'h36 : 8'h2d};
                        7'h24: usb_character = {1'b1, shifted ? 8'h37 : 8'h90}; // e grave
                        7'h25: usb_character = {1'b1, shifted ? 8'h38 : 8'h5f};
                        7'h26: usb_character = {1'b1, shifted ? 8'h39 :
                                               (caps ? 8'ha8 : 8'h88)}; // c cedilla
                        7'h27: usb_character = {1'b1, shifted ? 8'h30 : 8'h8d}; // a grave
                        7'h2d: usb_character = {1'b1, shifted ? 8'hba : 8'h29}; // degree
                        7'h2e: usb_character = {1'b1, shifted ? 8'h2b : 8'h3d};
                        7'h2f: usb_character = shifted ? 9'd0 : {1'b1, 8'h5e};
                        // The QL character set assigns pound to code 60.
                        7'h30: usb_character = {1'b1, shifted ? 8'h60 : 8'h24};
                        7'h31: usb_character = shifted ? 9'd0 :
                               {1'b1, 8'h2a};
                        7'h34: usb_character = {1'b1, shifted ? 8'h25 : 8'h9a}; // u grave
                        7'h36: usb_character = {1'b1, shifted ? 8'h2e : 8'h3b};
                        7'h37: usb_character = {1'b1, shifted ? 8'h2f : 8'h3a};
                        7'h38: usb_character = {1'b1, shifted ? 8'hb6 : 8'h21}; // section
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
                    7'h35: usb_character = {1'b1, shifted ? 8'h7e : 8'h9f};
                    7'h36: usb_character = {1'b1, shifted ? 8'h3c : 8'h2c};
                    7'h37: usb_character = {1'b1, shifted ? 8'h3e : 8'h2e};
                    7'h38: usb_character = {1'b1, shifted ? 8'h3f : 8'h2f};
                    7'h64: usb_character = {1'b1, shifted ? 8'h3e : 8'h3c};
                    default: usb_character = 9'd0;
                endcase
            end

            // Treat the numeric keypad as a stable QL numeric layer,
            // independently of Num Lock and of the selected PC layout.
            case (usage)
                7'h54: usb_character = {1'b1, 8'h2f}; // keypad /
                7'h55: usb_character = {1'b1, 8'h2a}; // keypad *
                7'h56: usb_character = {1'b1, 8'h2d}; // keypad -
                7'h57: usb_character = {1'b1, 8'h2b}; // keypad +
                7'h59: usb_character = {1'b1, 8'h31};
                7'h5a: usb_character = {1'b1, 8'h32};
                7'h5b: usb_character = {1'b1, 8'h33};
                7'h5c: usb_character = {1'b1, 8'h34};
                7'h5d: usb_character = {1'b1, 8'h35};
                7'h5e: usb_character = {1'b1, 8'h36};
                7'h5f: usb_character = {1'b1, 8'h37};
                7'h60: usb_character = {1'b1, 8'h38};
                7'h61: usb_character = {1'b1, 8'h39};
                7'h62: usb_character = {1'b1, 8'h30};
                7'h63: usb_character = {1'b1, 8'h2e}; // keypad decimal
                7'h67: usb_character = {1'b1, 8'h3d}; // keypad equals
                default: ;
            endcase
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
                      {1'b1, 3'b010, 7'h35} : {1'b1, 3'b001, 7'h23};
                8'h60: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h31} : {1'b1, 3'b000, 7'h32};
                8'h5c: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h2f} : {1'b1, 3'b000, 7'h31};
                "|": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h25} : {1'b1, 3'b001, 7'h31};
                "~": ql_character_key = french ?
                      {1'b1, 3'b010, 7'h31} : {1'b1, 3'b001, 7'h35};
                "/": ql_character_key = french ?
                      {1'b1, 3'b001, 7'h34} : {1'b1, 3'b000, 7'h38};
                "?": ql_character_key = {1'b1, 3'b001, 7'h38};
                8'h83: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h2f} : {1'b1, 3'b011, 7'h20}; // e acute
                8'h88: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h38} : {1'b1, 3'b011, 7'h26}; // c cedilla
                8'h8d: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h34} : {1'b1, 3'b010, 7'h2d}; // a grave
                8'h90: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h30} : {1'b1, 3'b010, 7'h27}; // e grave
                8'h9a: ql_character_key = french ?
                       {1'b1, 3'b000, 7'h31} : {1'b1, 3'b011, 7'h33}; // u grave
                8'h9f: ql_character_key = {1'b1, 3'b011, 7'h38}; // backtick
                8'ha3: ql_character_key = french ?
                       {1'b1, 3'b011, 7'h06} : {1'b1, 3'b011, 7'h06}; // E acute
                8'ha8: ql_character_key = french ?
                       {1'b1, 3'b011, 7'h0b} : {1'b1, 3'b011, 7'h0b}; // C cedilla
                8'hb6: ql_character_key = french ?
                       {1'b1, 3'b001, 7'h30} : {1'b1, 3'b011, 7'h19}; // section
                8'hba: ql_character_key = french ?
                       {1'b1, 3'b010, 7'h24} : {1'b1, 3'b011, 7'h1d}; // degree
                default: ql_character_key = 11'd0;
            endcase
        end
    endfunction

    wire azerty_number_caps = host_keyboard_azerty && usb_caps_lock &&
                              (data_in[6:0] >= 7'h1e) &&
                              (data_in[6:0] <= 7'h27);
    // ISO AZERTY keyboards disagree on whether the physical asterisk key is
    // usage 31 or 32. Normalize the alternate report before character
    // decoding instead of duplicating the complete translation mux.
    wire [6:0] character_usage =
        (host_keyboard_azerty && (data_in[6:0] == 7'h32)) ?
        7'h31 : data_in[6:0];
    wire [8:0] decoded_character = usb_character(
        character_usage, shift_down ^ azerty_number_caps,
        ctrl_down, alt_down,
        host_keyboard_azerty, usb_caps_lock
    );
    wire [10:0] semantic_key = ql_character_key(
        decoded_character[7:0], rom_keyboard_french
    );
    // On AZERTY, the physical US-M position (usage 0x10) carries comma and
    // question mark. Prefer a decoded printable character before treating a
    // usage in the nominal A-Z range as a letter.
    wire physical_letter = !decoded_character[8] &&
                           (data_in[6:0] >= 7'h04) &&
                           (data_in[6:0] <= 7'h1d);
    wire semantic_event = (decoded_character[8] && semantic_key[10]) ||
                          physical_letter;
    wire [6:0] semantic_usage = physical_letter ?
               translated_usage(data_in[6:0], shift_down) :
               semantic_key[6:0];
    wire host_letter_shift = shift_down ^ usb_caps_lock;
    wire [2:0] semantic_event_mods = physical_letter ?
               {alt_down, ctrl_down, host_letter_shift} : semantic_key[9:7];
    wire [2:0] host_event_mods = {alt_down, ctrl_down, shift_down};
    // Translation can remove a PC modifier as well as add a QL modifier.
    // For example, Shift+& on AZERTY means the unshifted QL digit 1. Keep the
    // main contact hidden while the IPC observes that Shift has disappeared;
    // otherwise keyboards which report Shift and the key very close together
    // can make the IPC reject the complete chord.
    wire semantic_event_needs_delay =
        (semantic_event_mods != 3'd0) ||
        (semantic_event_mods != host_event_mods);

    // Special PC keys become QL modifier combinations. Delay the main key
    // by about 22 ms so the IPC completes a matrix scan with the modifier
    // established before a contact on another row becomes visible.
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

    reg [63:0] semantic_matrix;
    reg semantic_active;
    reg semantic_shift;
    reg semantic_ctrl;
    reg semantic_alt;
    integer semantic_index;
    always @* begin
        semantic_matrix = 64'd0;
        semantic_active = 1'b0;
        semantic_shift = 1'b0;
        semantic_ctrl = 1'b0;
        semantic_alt = 1'b0;
        for (semantic_index = 0; semantic_index < 6;
             semantic_index = semantic_index + 1) begin
            if (semantic_valid[semantic_index]) begin
                semantic_active = 1'b1;
                // Present generated modifiers before the main contact. The
                // real IPC scans and debounces different matrix rows; making
                // both edges simultaneous can therefore lose Shift or Ctrl.
                if (semantic_hold[semantic_index] <= KEY_MIN_HOLD_TICKS)
                    semantic_matrix[semantic_contact[semantic_index]] = 1'b1;
                semantic_shift = semantic_shift |
                                 semantic_mods[semantic_index][0];
                semantic_ctrl = semantic_ctrl |
                                semantic_mods[semantic_index][1];
                semantic_alt = semantic_alt |
                               semantic_mods[semantic_index][2];
            end
        end
    end

    wire x_shift = (semantic_active ? semantic_shift : shift_down) ||
                   special[3] || special[4] ||
                   special[7] || special[8] || special[9] ||
                   special[10] || special[11];
    wire x_ctrl = (semantic_active ? semantic_ctrl : ctrl_down) ||
                  special[1] || special[2];
    wire x_alt = (semantic_active ? semantic_alt : alt_down) ||
                 special[5] || special[6];
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

    // USB Caps Lock is translated with PC semantics before the QL matrix:
    // letters use Caps XOR Shift, while digits and punctuation retain their
    // host-layout layers. The original QL Caps state would force uppercase
    // even with Shift, so it must not be toggled by a modern USB keyboard.
    assign matrix = ql_matrix | semantic_matrix | remote_matrix |
                    generated_matrix;

    always @(posedge clk) begin
        if (reset) begin
            delay_div <= 15'd0;
        end else begin
            delay_div <= delay_tick ? 15'd0 : delay_div + 15'd1;
        end
    end

    integer hold_index;
    always @(posedge clk) begin
        if (reset) begin
            state <= 4'd0;
            command <= 8'd0;
            data_out <= 8'd0;
            ql_matrix <= 64'd0;
            remote_matrix <= 64'd0;
            modifiers <= 6'd0;
            special <= 11'd0;
            semantic_valid <= 6'd0;
            semantic_release_pending <= 6'd0;
            usb_caps_lock <= 1'b0;
            key_event <= 1'b0;
            key_press_event <= 1'b0;
        end else begin
            for (hold_index = 0; hold_index < 6;
                 hold_index = hold_index + 1) begin
                if (semantic_valid[hold_index] &&
                    (semantic_hold[hold_index] != 7'd0) && delay_tick)
                    semantic_hold[hold_index] <=
                        semantic_hold[hold_index] - 7'd1;
            end
            // Retire at most one expired key per clock. This keeps the
            // registered matrix update shallow while simultaneous releases
            // are still drained on consecutive 74 MHz cycles.
            if (semantic_valid[0] && semantic_release_pending[0] &&
                (semantic_hold[0] == 7'd0)) begin
                semantic_valid[0] <= 1'b0;
                semantic_release_pending[0] <= 1'b0;
            end else if (semantic_valid[1] && semantic_release_pending[1] &&
                (semantic_hold[1] == 7'd0)) begin
                semantic_valid[1] <= 1'b0;
                semantic_release_pending[1] <= 1'b0;
            end else if (semantic_valid[2] && semantic_release_pending[2] &&
                (semantic_hold[2] == 7'd0)) begin
                semantic_valid[2] <= 1'b0;
                semantic_release_pending[2] <= 1'b0;
            end else if (semantic_valid[3] && semantic_release_pending[3] &&
                (semantic_hold[3] == 7'd0)) begin
                semantic_valid[3] <= 1'b0;
                semantic_release_pending[3] <= 1'b0;
            end else if (semantic_valid[4] && semantic_release_pending[4] &&
                (semantic_hold[4] == 7'd0)) begin
                semantic_valid[4] <= 1'b0;
                semantic_release_pending[4] <= 1'b0;
            end else if (semantic_valid[5] && semantic_release_pending[5] &&
                (semantic_hold[5] == 7'd0)) begin
                semantic_valid[5] <= 1'b0;
                semantic_release_pending[5] <= 1'b0;
            end
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
                        if ((command == 8'd1) && semantic_event) begin
                            if (data_in[7]) begin
                                if (semantic_valid[0] &&
                                    (semantic_raw[0] == data_in[6:0])) begin
                                    if (semantic_hold[0] == 7'd0) begin
                                        semantic_valid[0] <= 1'b0;
                                    end else
                                        semantic_release_pending[0] <= 1'b1;
                                end
                                if (semantic_valid[1] &&
                                    (semantic_raw[1] == data_in[6:0])) begin
                                    if (semantic_hold[1] == 7'd0) begin
                                        semantic_valid[1] <= 1'b0;
                                    end else
                                        semantic_release_pending[1] <= 1'b1;
                                end
                                if (semantic_valid[2] &&
                                    (semantic_raw[2] == data_in[6:0])) begin
                                    if (semantic_hold[2] == 7'd0) begin
                                        semantic_valid[2] <= 1'b0;
                                    end else
                                        semantic_release_pending[2] <= 1'b1;
                                end
                                if (semantic_valid[3] &&
                                    (semantic_raw[3] == data_in[6:0])) begin
                                    if (semantic_hold[3] == 7'd0) begin
                                        semantic_valid[3] <= 1'b0;
                                    end else
                                        semantic_release_pending[3] <= 1'b1;
                                end
                                if (semantic_valid[4] &&
                                    (semantic_raw[4] == data_in[6:0])) begin
                                    if (semantic_hold[4] == 7'd0) begin
                                        semantic_valid[4] <= 1'b0;
                                    end else
                                        semantic_release_pending[4] <= 1'b1;
                                end
                                if (semantic_valid[5] &&
                                    (semantic_raw[5] == data_in[6:0])) begin
                                    if (semantic_hold[5] == 7'd0) begin
                                        semantic_valid[5] <= 1'b0;
                                    end else
                                        semantic_release_pending[5] <= 1'b1;
                                end
                            end else begin
                                if (!semantic_valid[0] ||
                                    (semantic_raw[0] == data_in[6:0])) begin
                                    semantic_valid[0] <= 1'b1;
                                    semantic_raw[0] <= data_in[6:0];
                                    semantic_contact[0] <=
                                        usage_contact(semantic_usage);
                                    semantic_mods[0] <= semantic_event_mods;
                                    semantic_hold[0] <=
                                        semantic_event_needs_delay ?
                                        KEY_TOTAL_HOLD_TICKS :
                                        KEY_MIN_HOLD_TICKS;
                                    semantic_release_pending[0] <= 1'b0;
                                end else if (!semantic_valid[1] ||
                                    (semantic_raw[1] == data_in[6:0])) begin
                                    semantic_valid[1] <= 1'b1;
                                    semantic_raw[1] <= data_in[6:0];
                                    semantic_contact[1] <=
                                        usage_contact(semantic_usage);
                                    semantic_mods[1] <= semantic_event_mods;
                                    semantic_hold[1] <=
                                        semantic_event_needs_delay ?
                                        KEY_TOTAL_HOLD_TICKS :
                                        KEY_MIN_HOLD_TICKS;
                                    semantic_release_pending[1] <= 1'b0;
                                end else if (!semantic_valid[2] ||
                                    (semantic_raw[2] == data_in[6:0])) begin
                                    semantic_valid[2] <= 1'b1;
                                    semantic_raw[2] <= data_in[6:0];
                                    semantic_contact[2] <=
                                        usage_contact(semantic_usage);
                                    semantic_mods[2] <= semantic_event_mods;
                                    semantic_hold[2] <=
                                        semantic_event_needs_delay ?
                                        KEY_TOTAL_HOLD_TICKS :
                                        KEY_MIN_HOLD_TICKS;
                                    semantic_release_pending[2] <= 1'b0;
                                end else if (!semantic_valid[3] ||
                                    (semantic_raw[3] == data_in[6:0])) begin
                                    semantic_valid[3] <= 1'b1;
                                    semantic_raw[3] <= data_in[6:0];
                                    semantic_contact[3] <=
                                        usage_contact(semantic_usage);
                                    semantic_mods[3] <= semantic_event_mods;
                                    semantic_hold[3] <=
                                        semantic_event_needs_delay ?
                                        KEY_TOTAL_HOLD_TICKS :
                                        KEY_MIN_HOLD_TICKS;
                                    semantic_release_pending[3] <= 1'b0;
                                end else if (!semantic_valid[4] ||
                                    (semantic_raw[4] == data_in[6:0])) begin
                                    semantic_valid[4] <= 1'b1;
                                    semantic_raw[4] <= data_in[6:0];
                                    semantic_contact[4] <=
                                        usage_contact(semantic_usage);
                                    semantic_mods[4] <= semantic_event_mods;
                                    semantic_hold[4] <=
                                        semantic_event_needs_delay ?
                                        KEY_TOTAL_HOLD_TICKS :
                                        KEY_MIN_HOLD_TICKS;
                                    semantic_release_pending[4] <= 1'b0;
                                end else if (!semantic_valid[5] ||
                                    (semantic_raw[5] == data_in[6:0])) begin
                                    semantic_valid[5] <= 1'b1;
                                    semantic_raw[5] <= data_in[6:0];
                                    semantic_contact[5] <=
                                        usage_contact(semantic_usage);
                                    semantic_mods[5] <= semantic_event_mods;
                                    semantic_hold[5] <=
                                        semantic_event_needs_delay ?
                                        KEY_TOTAL_HOLD_TICKS :
                                        KEY_MIN_HOLD_TICKS;
                                    semantic_release_pending[5] <= 1'b0;
                                end
                            end
                        end
                        if (!((command == 8'd1) && semantic_event))
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
                            7'h58: ql_matrix[8] <= !data_in[7]; // keypad Enter

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
                        semantic_valid <= 6'd0;
                        semantic_release_pending <= 6'd0;
                        usb_caps_lock <= data_in[1];
                    end

                    // Command 8 updates only the authoritative physical USB
                    // Caps Lock state. Unlike command 7 it never clears held
                    // keys or modifiers.
                    if ((command == 8'd8) && (state == 4'd0)) begin
                        usb_caps_lock <= data_in[1];
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
