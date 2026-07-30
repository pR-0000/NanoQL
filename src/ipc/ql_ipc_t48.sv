module ql_ipc_t48(
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_11m,
    input  wire       comdata_in,
    input  wire [63:0] keyboard_matrix,
    input  wire       rom_write_enable,
    input  wire [10:0] rom_write_address,
    input  wire [7:0] rom_write_data,
    output wire       comctrl,
    output wire       comdata_out,
    output wire       audio,
    output wire [1:0] ipl
);

    wire [7:0] p1_out;
    wire [7:0] p2_out;
    wire [7:0] p2_in = {comdata_out && comdata_in, 7'b0000000};
    wire unused_t0;
    wire unused_t0_dir;
    wire unused_rd_n;
    wire unused_psen_n;
    wire unused_ale;
    wire [7:0] unused_db;
    wire unused_db_dir;
    wire unused_p2l;
    wire p2_write_strobe;
    wire unused_p1_low;
    wire unused_prog_n;

    // During MOVX cycles, a physical MCS-48 temporarily drives the external
    // address on the low half of P2. Keep the last actual port-register value
    // so those bus phases cannot leak into BEEP or the QL interrupt lines.
    reg [7:0] p2_port = 8'hff;
    always @(posedge clk) begin
        if (reset)
            p2_port <= 8'hff;
        else if (p2_write_strobe)
            p2_port <= p2_out;
    end

    assign comdata_out = p2_port[7];
    assign audio = p2_port[1];
    assign ipl = p2_port[3:2];
    wire [7:0] keyboard_data =
        (p1_out[0] ? keyboard_matrix[7:0] : 8'h00) |
        (p1_out[1] ? keyboard_matrix[15:8] : 8'h00) |
        (p1_out[2] ? keyboard_matrix[23:16] : 8'h00) |
        (p1_out[3] ? keyboard_matrix[31:24] : 8'h00) |
        (p1_out[4] ? keyboard_matrix[39:32] : 8'h00) |
        (p1_out[5] ? keyboard_matrix[47:40] : 8'h00) |
        (p1_out[6] ? keyboard_matrix[55:48] : 8'h00) |
        (p1_out[7] ? keyboard_matrix[63:56] : 8'h00);

    t8049_notri #(
        .gate_port_input_g(0)
    ) ipc_cpu (
        .xtal_i(clk),
        .xtal_en_i(ce_11m),
        .reset_n_i(!reset),
        .t0_i(1'b0),
        .t0_o(unused_t0),
        .t0_dir_o(unused_t0_dir),
        .int_n_i(1'b1),
        .ea_i(1'b0),
        .rd_n_o(unused_rd_n),
        .psen_n_o(unused_psen_n),
        .wr_n_o(comctrl),
        .ale_o(unused_ale),
        .db_i(keyboard_data),
        .db_o(unused_db),
        .db_dir_o(unused_db_dir),
        .t1_i(1'b0),
        .p2_i(p2_in),
        .p2_o(p2_out),
        .p2l_low_imp_o(unused_p2l),
        .p2h_low_imp_o(p2_write_strobe),
        .p1_i(8'h00),
        .p1_o(p1_out),
        .p1_low_imp_o(unused_p1_low),
        .prog_n_o(unused_prog_n),
        .rom_we_i(rom_write_enable),
        .rom_waddr_i(rom_write_address),
        .rom_wdata_i(rom_write_data)
    );

endmodule
