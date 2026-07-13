// Sinclair QL RAM timing model, adapted from QL_MiSTer's rtl/ql_timing.sv.
// Copyright (C) 2019 Marcel Kilgus
// Copyright (c) 2021 Daniele Terdina
// GPL-3.0-or-later
module ql_timing (
    input  wire clk_sys,
    input  wire reset,
    input  wire enable,
    input  wire ce_bus_p,
    input  wire vblank,
    input  wire cpu_uds,
    input  wire cpu_lds,
    input  wire cpu_rw,
    input  wire cpu_rom,
    output reg  ram_delay_dtack
);

    reg [5:0] chunk;
    reg [3:0] chunk_cycle;
    reg prev_ds;
    reg [2:0] dtack_count;
    reg extra_access;

    wire [5:0] busy_chunks = vblank ? 6'd8 : 6'd32;
    wire could_start = (chunk >= busy_chunks) || (chunk_cycle == 4'd0);
    wire ds = cpu_uds || cpu_lds;

    always @(posedge clk_sys) begin
        if (reset || !enable) begin
            chunk <= 6'd0;
            chunk_cycle <= 4'd0;
            prev_ds <= 1'b0;
            dtack_count <= 3'd0;
            extra_access <= 1'b0;
            ram_delay_dtack <= 1'b0;
        end else if (ce_bus_p) begin
            if (chunk_cycle == 4'd11) begin
                chunk_cycle <= 4'd0;
                chunk <= (chunk == 6'd39) ? 6'd0 : chunk + 6'd1;
            end else begin
                chunk_cycle <= chunk_cycle + 4'd1;
            end

            if (ds && !prev_ds) begin
                ram_delay_dtack <= 1'b1;
                dtack_count <= 3'd1;
                extra_access <= cpu_uds && cpu_lds;
            end else if (ram_delay_dtack) begin
                if (dtack_count == 3'd1) begin
                    if (could_start || cpu_rom) begin
                        if (extra_access) begin
                            dtack_count <= cpu_rw ? 3'd4 : 3'd5;
                            extra_access <= 1'b0;
                        end else begin
                            ram_delay_dtack <= 1'b0;
                            dtack_count <= 3'd0;
                        end
                    end
                end else if (dtack_count != 3'd0) begin
                    dtack_count <= dtack_count - 3'd1;
                end
            end

            prev_ds <= ds;
        end
    end

endmodule
