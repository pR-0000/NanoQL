module ql_cpu_fx68k(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [1:0]  ram_config,
    input  wire [1:0]  cpu_speed,

    output wire [23:0] cpu_addr,
    output wire [15:0] cpu_data_out,
    input  wire [15:0] cpu_data_in,
    output wire        cpu_as_n,
    output wire        cpu_rw,
    output wire        cpu_uds_n,
    output wire        cpu_lds_n,
    input  wire        cpu_dtack_n,
    input  wire [2:0]  cpu_ipl_n,
    output wire [2:0]  cpu_fc,
    output wire        ce_bus_p,
    output wire        ce_bus_n,

    input  wire [4:0]  debug_reg_select,
    input  wire [4:0]  debug_bit_select,
    output wire        debug_reg_bit,
    output wire [31:0] debug_pc,
    output wire [15:0] debug_sr,
    output wire [15:0] debug_ir
);

    wire cpu_reset = reset;
    wire en_phi1;
    wire en_phi2;
    wire [23:1] cpu_word_addr;
    wire cpu_vpa_n = (cpu_fc != 3'b111);

    ql_cpu_phase phase_generator (
        .clk(clk),
        .reset(cpu_reset),
        .enable(enable),
        .cpu_speed(cpu_speed),
        .en_phi1(en_phi1),
        .en_phi2(en_phi2)
    );

    assign ce_bus_p = en_phi1;
    assign ce_bus_n = en_phi2;

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
        .FC0(cpu_fc[0]),
        .FC1(cpu_fc[1]),
        .FC2(cpu_fc[2]),
        .BGn(),
        .oRESETn(),
        .oHALTEDn(),
        .DTACKn(cpu_dtack_n),
        .VPAn(cpu_vpa_n),
        .BERRn(1'b1),
        .BRn(1'b1),
        .BGACKn(1'b1),
        .IPL0n(cpu_ipl_n[0]),
        .IPL1n(cpu_ipl_n[1]),
        .IPL2n(cpu_ipl_n[2]),
        .iEdb(cpu_data_in),
        .oEdb(cpu_data_out),
        .eab(cpu_word_addr),
        .debug_reg_select(debug_reg_select),
        .debug_bit_select(debug_bit_select),
        .debug_reg_bit(debug_reg_bit),
        .debug_pc(debug_pc),
        .debug_sr(debug_sr),
        .debug_ir(debug_ir)
    );

    // fx68k exposes A23..A1; reconstruct the byte address using the base-QL
    // decoder shared with the standalone address-map regression test.
    ql_cpu_address address_decoder (
        .word_addr(cpu_word_addr),
        .uds_n(cpu_uds_n),
        .lds_n(cpu_lds_n),
        .ram_config(ram_config),
        .byte_addr(cpu_addr)
    );

endmodule
