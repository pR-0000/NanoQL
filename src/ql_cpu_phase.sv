module ql_cpu_phase (
    input  wire       clk,
    input  wire       reset,
    input  wire [1:0] cpu_speed,
    output reg        en_phi1,
    output reg        en_phi2
);

    // 31.8 MHz * 30913 / 65536 = 15.000 MHz phase events, alternating
    // between Phi1 and Phi2 for the original 7.5 MHz QL CPU rate.
    localparam [15:0] QL_PHASE_STEP = 16'd30913;

    reg [15:0] phase_accum;
    reg phase_polarity;
    wire [16:0] ql_phase_sum = {1'b0, phase_accum} +
                               {1'b0, QL_PHASE_STEP};
    wire phase_tick = (cpu_speed == 2'd0) ? ql_phase_sum[16] : 1'b1;

    always @(posedge clk) begin
        if (reset) begin
            phase_accum <= 16'd0;
            phase_polarity <= 1'b0;
            en_phi1 <= 1'b0;
            en_phi2 <= 1'b0;
        end else begin
            phase_accum <= (cpu_speed == 2'd0) ?
                           ql_phase_sum[15:0] : 16'd0;
            en_phi1 <= phase_tick && !phase_polarity;
            en_phi2 <= phase_tick && phase_polarity;
            if (phase_tick)
                phase_polarity <= !phase_polarity;
        end
    end

endmodule
