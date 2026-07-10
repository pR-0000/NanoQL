module ql_cpu_fx68k(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    output wire [23:0] cpu_addr,
    output wire [15:0] cpu_data_out,
    input  wire [15:0] cpu_data_in,
    output wire        cpu_as_n,
    output wire        cpu_rw,
    output wire        cpu_uds_n,
    output wire        cpu_lds_n,
    input  wire        cpu_dtack_n,
    input  wire [2:0]  cpu_ipl_n
);

    reg [1:0] phase_div;
    wire cpu_reset = reset || !enable;
    wire en_phi1 = enable && (phase_div == 2'b11);
    wire en_phi2 = enable && (phase_div == 2'b01);
    wire [23:1] cpu_word_addr;

    always @(posedge clk) begin
        if (cpu_reset)
            phase_div <= 2'd0;
        else
            phase_div <= phase_div + 2'd1;
    end

    // A 31.8 MHz system clock divided into two phase enables gives a
    // transitional 7.95 MHz 68000 clock, close to the original QL rate.
    fx68k cpu (
        .clk(clk),
        .HALTn(1'b1),
        .extReset(cpu_reset),
        .pwrUp(cpu_reset),
        .enPhi1(en_phi1),
        .enPhi2(en_phi2),
        .eRWn(cpu_rw),
        .ASn(cpu_as_n),
        .LDSn(cpu_lds_n),
        .UDSn(cpu_uds_n),
        .E(),
        .VMAn(),
        .FC0(),
        .FC1(),
        .FC2(),
        .BGn(),
        .oRESETn(),
        .oHALTEDn(),
        .DTACKn(cpu_dtack_n),
        .VPAn(1'b1),
        .BERRn(1'b1),
        .BRn(1'b1),
        .BGACKn(1'b1),
        .IPL0n(cpu_ipl_n[0]),
        .IPL1n(cpu_ipl_n[1]),
        .IPL2n(cpu_ipl_n[2]),
        .iEdb(cpu_data_in),
        .oEdb(cpu_data_out),
        .eab(cpu_word_addr)
    );

    assign cpu_addr = {cpu_word_addr, 1'b0};

endmodule
