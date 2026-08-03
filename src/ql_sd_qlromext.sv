// SPDX-License-Identifier: GPL-3.0-or-later
// QLROMEXT-compatible register and SPI logic for QL-SD.
// Based on the QL_MiSTer/QL-SD implementation by Adrian Ives and Peter Graf.

module ql_sd_qlromext #(
    // Preserve the original absolute delays in NanoQL's 48 MHz domain.
    parameter integer DTACK_DELAY = 26,
    parameter integer SLOW_DIVIDER = 71
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_sd,
    input  wire        romoel,
    input  wire [15:0] address,
    output wire [7:0]  data_out,
    output wire        dtack,
    output wire        sd_clk,
    output wire        sd_cs1_n,
    output wire        sd_cs2_n,
    output wire        sd_mosi,
    input  wire        sd_miso
);

    localparam [15:0] IF_ENABLE     = 16'hfee0;
    localparam [15:0] IF_DISABLE    = 16'hfee1;
    localparam [15:0] IF_RESET      = 16'hfee2;
    localparam [15:0] SPI_READ      = 16'hfee4;
    localparam [15:0] SPI_FAST      = 16'hfee6;
    localparam [15:0] SPI_SLOW      = 16'hfee8;
    localparam [15:0] SPI_OFF       = 16'hfeea;
    localparam [15:0] SPI_DESELECT  = 16'hfef0;
    localparam [15:0] SPI_SELECT1   = 16'hfef1;
    localparam [15:0] SPI_SELECT2   = 16'hfef2;
    localparam [15:0] SPI_CLR_MOSI  = 16'hfef4;
    localparam [15:0] SPI_SET_MOSI  = 16'hfef5;
    localparam [15:0] SPI_CLR_SCLK  = 16'hfef6;
    localparam [15:0] SPI_SET_SCLK  = 16'hfef7;

    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_PROLOGUE = 3'd1;
    localparam [2:0] ST_DIVIDE   = 3'd2;
    localparam [2:0] ST_SHIFT    = 3'd3;
    localparam [2:0] ST_DONE     = 3'd4;
    localparam [2:0] ST_RELEASE  = 3'd5;

    reg interface_enabled;
    reg cs1_n;
    reg cs2_n;
    reg fg_mosi;
    reg fg_sclk;
    reg bg_mosi;
    reg bg_sclk;
    reg bg_enabled;
    reg spi_fast;
    reg transfer_running;
    reg [7:0] shift_reg;
    reg [3:0] bit_counter;
    reg [6:0] slow_counter;
    reg [2:0] spi_state;
    reg previous_romoel;
    reg [6:0] dtack_counter;
    reg dtack_reg;

    assign sd_mosi = transfer_running ? bg_mosi : fg_mosi;
    assign sd_clk = transfer_running ? bg_sclk : fg_sclk;
    assign sd_cs1_n = interface_enabled ? cs1_n : 1'b1;
    assign sd_cs2_n = interface_enabled ? cs2_n : 1'b1;
    assign data_out = interface_enabled && (address == SPI_READ) ?
                      (bg_enabled ? shift_reg : {7'd0, sd_miso}) : 8'h00;
    assign dtack = dtack_reg;

    always @(posedge clk) begin
        dtack_reg <= 1'b0;
        previous_romoel <= romoel;

        if (reset) begin
            interface_enabled <= 1'b0;
            cs1_n <= 1'b1;
            cs2_n <= 1'b1;
            fg_mosi <= 1'b1;
            fg_sclk <= 1'b1;
            bg_mosi <= 1'b1;
            bg_sclk <= 1'b1;
            bg_enabled <= 1'b0;
            spi_fast <= 1'b0;
            transfer_running <= 1'b0;
            shift_reg <= 8'd0;
            bit_counter <= 4'd0;
            slow_counter <= 7'd0;
            spi_state <= ST_IDLE;
            previous_romoel <= 1'b1;
            dtack_counter <= 7'd0;
            dtack_reg <= 1'b0;
        end else begin
            if (dtack_counter != 0)
                dtack_counter <= dtack_counter - 7'd1;
            if (!previous_romoel && !romoel && dtack_counter == 1)
                dtack_reg <= 1'b1;

            // QLROMEXT control operations are encoded as reads from these
            // addresses, exactly as on the physical expansion board.
            if (!romoel && previous_romoel) begin
                dtack_counter <= DTACK_DELAY;
                case (address)
                    IF_ENABLE: interface_enabled <= 1'b1;
                    IF_DISABLE: interface_enabled <= 1'b0;
                    IF_RESET: begin
                        fg_mosi <= 1'b1;
                        fg_sclk <= 1'b1;
                        cs1_n <= 1'b1;
                        cs2_n <= 1'b1;
                        spi_fast <= 1'b0;
                        bg_enabled <= 1'b0;
                    end
                    SPI_FAST: begin spi_fast <= 1'b1; bg_enabled <= 1'b1; end
                    SPI_SLOW: begin spi_fast <= 1'b0; bg_enabled <= 1'b1; end
                    SPI_OFF: bg_enabled <= 1'b0;
                    SPI_DESELECT: begin cs1_n <= 1'b1; cs2_n <= 1'b1; end
                    SPI_SELECT1: begin cs1_n <= 1'b0; cs2_n <= 1'b1; end
                    SPI_SELECT2: begin cs1_n <= 1'b1; cs2_n <= 1'b0; end
                    SPI_CLR_MOSI: fg_mosi <= 1'b0;
                    SPI_SET_MOSI: fg_mosi <= 1'b1;
                    SPI_CLR_SCLK: fg_sclk <= 1'b0;
                    SPI_SET_SCLK: fg_sclk <= 1'b1;
                    default: ;
                endcase
            end

            if (ce_sd) begin
                case (spi_state)
                    ST_IDLE:
                        if (interface_enabled && bg_enabled && !romoel &&
                            address[15:8] == 8'hff)
                            spi_state <= ST_PROLOGUE;
                    ST_PROLOGUE: begin
                        shift_reg <= address[7:0];
                        bg_mosi <= 1'b1;
                        bg_sclk <= 1'b1;
                        bit_counter <= 4'd0;
                        slow_counter <= SLOW_DIVIDER;
                        transfer_running <= 1'b1;
                        spi_state <= spi_fast ? ST_SHIFT : ST_DIVIDE;
                    end
                    ST_DIVIDE: begin
                        if (slow_counter == 0)
                            spi_state <= ST_SHIFT;
                        else
                            slow_counter <= slow_counter - 7'd1;
                    end
                    ST_SHIFT: begin
                        bg_sclk <= !bg_sclk;
                        bit_counter <= bit_counter + 4'd1;
                        if (bg_sclk)
                            bg_mosi <= shift_reg[7];
                        else
                            shift_reg <= {shift_reg[6:0], sd_miso};
                        slow_counter <= SLOW_DIVIDER;
                        if (bit_counter == 4'd15)
                            spi_state <= ST_DONE;
                        else
                            spi_state <= spi_fast ? ST_SHIFT : ST_DIVIDE;
                    end
                    ST_DONE: begin
                        transfer_running <= 1'b0;
                        bg_mosi <= 1'b1;
                        spi_state <= ST_RELEASE;
                    end
                    default:
                        if (romoel || address[15:8] != 8'hff)
                            spi_state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
