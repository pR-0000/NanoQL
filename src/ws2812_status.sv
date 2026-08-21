// Drives the Tang Nano 20K on-board WS2812 from the 27 MHz oscillator.
// The LED is off normally and dim green while Caps Lock is active.
module ws2812_status (
    input  wire clk_27m,
    input  wire reset,
    input  wire caps_lock_active,
    output reg  data_out
);
    localparam integer BIT_TICKS   = 34;      // 1.26 us
    localparam integer ZERO_TICKS  = 11;      // 0.41 us high
    localparam integer ONE_TICKS   = 23;      // 0.85 us high
    localparam integer RESET_TICKS = 2700000; // 100 ms low

    reg caps_meta;
    reg caps_sync;
    reg sending;
    reg [5:0] bit_tick;
    reg [4:0] bit_index;
    reg [21:0] reset_tick;
    reg [23:0] color_grb;

    always @(posedge clk_27m) begin
        caps_meta <= caps_lock_active;
        caps_sync <= caps_meta;

        if (reset) begin
            caps_meta <= 1'b0;
            caps_sync <= 1'b0;
            data_out <= 1'b0;
            sending <= 1'b0;
            bit_tick <= 6'd0;
            bit_index <= 5'd23;
            reset_tick <= 22'd0;
            color_grb <= 24'd0;
        end else if (sending) begin
            data_out <= color_grb[bit_index] ?
                        (bit_tick < ONE_TICKS) :
                        (bit_tick < ZERO_TICKS);

            if (bit_tick == BIT_TICKS - 1) begin
                bit_tick <= 6'd0;
                if (bit_index == 0) begin
                    sending <= 1'b0;
                    reset_tick <= 22'd0;
                    data_out <= 1'b0;
                end else begin
                    bit_index <= bit_index - 1'b1;
                end
            end else begin
                bit_tick <= bit_tick + 1'b1;
            end
        end else begin
            data_out <= 1'b0;
            if (reset_tick == RESET_TICKS - 1) begin
                reset_tick <= 22'd0;
                // Clearly visible through the board diffuser while remaining
                // much dimmer than the WS2812 maximum.
                color_grb <= caps_sync ? 24'h300000 : 24'h000000;
                bit_index <= 5'd23;
                bit_tick <= 6'd0;
                sending <= 1'b1;
            end else begin
                reset_tick <= reset_tick + 1'b1;
            end
        end
    end
endmodule
