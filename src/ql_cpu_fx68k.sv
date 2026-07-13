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
    input  wire [2:0]  cpu_ipl_n,
    output wire [2:0]  cpu_fc,
    output wire        ce_bus_p,
    output wire        ce_bus_n
);

    // QL_MiSTer drives fx68k with alternating 15 MHz phase enables to model
    // the original 7.5 MHz 68008. The 31.8 MHz NanoQL system clock therefore
    // needs a fractional divider rather than the former divide-by-four clock.
    localparam [15:0] PHASE_STEP = 16'd30913;
    reg [15:0] phase_accum;
    reg phase_polarity;
    wire [16:0] phase_sum = {1'b0, phase_accum} + {1'b0, PHASE_STEP};
    wire phase_tick = phase_sum[16];
    wire cpu_reset = reset || !enable;
    reg en_phi1;
    reg en_phi2;
    wire [23:1] cpu_word_addr;
    wire cpu_vpa_n = (cpu_fc != 3'b111);

    // QL_MiSTer prepares these enables on the opposite clock edge. On Gowin,
    // register them one rising edge ahead instead: all consumers observe the
    // previous registered value, giving a full system cycle of setup time
    // without introducing an inverted internal clock domain.
    always @(posedge clk) begin
        if (cpu_reset) begin
            phase_accum <= 16'd0;
            phase_polarity <= 1'b0;
            en_phi1 <= 1'b0;
            en_phi2 <= 1'b0;
        end else begin
            phase_accum <= phase_sum[15:0];
            en_phi1 <= phase_tick && !phase_polarity;
            en_phi2 <= phase_tick && phase_polarity;
            if (phase_tick)
                phase_polarity <= !phase_polarity;
        end
    end

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
        .eab(cpu_word_addr)
    );

    // fx68k exposes A23..A1; reconstruct the byte address using the base-QL
    // decoder shared with the standalone address-map regression test.
    ql_cpu_address address_decoder (
        .word_addr(cpu_word_addr),
        .uds_n(cpu_uds_n),
        .lds_n(cpu_lds_n),
        .byte_addr(cpu_addr)
    );

endmodule
