module ql_ipc_t48(
    input  wire       clk,
    input  wire       reset,
    input  wire       comdata_in,
    input  wire [63:0] keyboard_matrix,
    output wire       comctrl,
    output wire       comdata_out,
    output wire       audio,
    output wire [1:0] ipl
);

    reg [1:0] ipc_clock_div;
    wire ipc_clock_enable = (ipc_clock_div == 2'd2);

    always @(posedge clk) begin
        if (reset)
            ipc_clock_div <= 2'd0;
        else if (ipc_clock_enable)
            ipc_clock_div <= 2'd0;
        else
            ipc_clock_div <= ipc_clock_div + 2'd1;
    end

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
    wire unused_p2h;
    wire unused_p1_low;
    wire unused_prog_n;

    assign comdata_out = p2_out[7];
    assign audio = p2_out[1];
    assign ipl = p2_out[3:2];
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
        .xtal_en_i(ipc_clock_enable),
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
        .p2h_low_imp_o(unused_p2h),
        .p1_i(8'h00),
        .p1_o(p1_out),
        .p1_low_imp_o(unused_p1_low),
        .prog_n_o(unused_prog_n)
    );

endmodule
