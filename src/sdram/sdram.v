//
// SDRAM controller implementation for the Tang Nano 20K.
// Transaction timing imported from MiSTeryNano: src/tang/nano20k/sdram.v
//
// Copyright (c) 2023 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//

module sdram #(
    parameter integer CLOCK_HZ = 48_000_000
) (
    output             sd_clk,
    output             sd_cke,
    inout reg [31:0]   sd_data,
    output reg [12:0]  sd_addr,
    output [3:0]       sd_dqm,
    output reg [1:0]   sd_ba,
    output             sd_cs,
    output             sd_we,
    output             sd_ras,
    output             sd_cas,

    input              clk,
    input              reset_n,
    output             ready,
    input              refresh,
    input [15:0]       din,
    output reg [15:0]  dout,
    input [21:0]       addr,
    input [1:0]        ds,
    input              cs,
    input              we
);

assign sd_clk = ~clk;
assign sd_cke = 1'b1;

localparam RASCAS_DELAY   = 3'd1;
localparam BURST_LENGTH   = 3'b000;
localparam ACCESS_TYPE    = 1'b0;
localparam CAS_LATENCY    = 3'd2;
localparam OP_MODE        = 2'b00;
localparam NO_WRITE_BURST = 1'b1;
localparam MODE = {1'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY,
                   ACCESS_TYPE, BURST_LENGTH};

localparam STATE_IDLE     = 3'd0;
localparam STATE_CMD_CONT = STATE_IDLE + RASCAS_DELAY;
localparam STATE_READ     = STATE_CMD_CONT + CAS_LATENCY + 3'd1;
localparam STATE_LAST     = 3'd6;
localparam integer POWER_UP_CYCLES = (CLOCK_HZ / 5_000) + 1;

reg [2:0] state;
reg [4:0] init_state;
reg [15:0] power_up_count;
reg power_up_done;
assign ready = power_up_done && !(|init_state);

localparam CMD_INHIBIT      = 4'b1111;
localparam CMD_NOP          = 4'b0111;
localparam CMD_ACTIVE       = 4'b0011;
localparam CMD_READ         = 4'b0101;
localparam CMD_WRITE        = 4'b0100;
localparam CMD_PRECHARGE    = 4'b0010;
localparam CMD_AUTO_REFRESH = 4'b0001;
localparam CMD_LOAD_MODE    = 4'b0000;

reg [3:0] sd_cmd;
assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

assign sd_data = (cs && we) ? {din, din} : 32'bz;
assign sd_dqm = (!cs || !we) ? 4'b0000 :
                addr[0] ? {2'b11, ds} : {ds, 2'b11};

always @(posedge clk) begin
    reg cs_d;

    sd_cmd <= CMD_INHIBIT;

    if (!reset_n) begin
        init_state <= 5'h1f;
        power_up_count <= 16'd0;
        power_up_done <= 1'b0;
        state <= STATE_IDLE;
        cs_d <= 1'b0;
    end else if (!power_up_done) begin
        // Keep the SDRAM inhibited for 200 us after the clock becomes stable.
        state <= STATE_IDLE;
        cs_d <= 1'b0;
        if (power_up_count == POWER_UP_CYCLES - 1)
            power_up_done <= 1'b1;
        else
            power_up_count <= power_up_count + 16'd1;
    end else begin
        if (init_state != 0)
            state <= state + 3'd1;

        if ((state == STATE_LAST) && (init_state != 0))
            init_state <= init_state - 5'd1;

        if (init_state != 0) begin
            cs_d <= 1'b0;

            if (state == STATE_IDLE) begin
                if (init_state == 5'd13) begin
                    sd_cmd <= CMD_PRECHARGE;
                    sd_addr[10] <= 1'b1;
                end

                // Two refreshes follow PRECHARGE ALL before the mode register.
                if ((init_state == 5'd12) || (init_state == 5'd11))
                    sd_cmd <= CMD_AUTO_REFRESH;

                if (init_state == 5'd2) begin
                    sd_cmd <= CMD_LOAD_MODE;
                    sd_addr <= MODE;
                end
            end
        end else begin
            cs_d <= cs;

            // Preserve MiSTeryNano's proven command and read-capture phases.
            if (state == STATE_IDLE) begin
                if (cs && !cs_d) begin
                    if (!refresh) begin
                        sd_cmd <= CMD_ACTIVE;
                        sd_addr <= addr[19:9];
                        sd_ba <= addr[21:20];
                        state <= 3'd1;
                    end else begin
                        sd_cmd <= CMD_AUTO_REFRESH;
                    end
                end
            end else begin
                state <= state + 3'd1;

                if (state == STATE_CMD_CONT) begin
                    sd_cmd <= we ? CMD_WRITE : CMD_READ;
                    sd_addr <= {3'b100, addr[8:1]};
                end

                if ((state > STATE_CMD_CONT) && (state < STATE_READ))
                    sd_cmd <= CMD_NOP;

                if ((state == STATE_READ) && !we)
                    dout <= addr[0] ? sd_data[15:0] : sd_data[31:16];
            end
        end
    end
end

endmodule
