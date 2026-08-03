module ql_cpu_phase (
    input  wire       clk,
    input  wire       reset,
    input  wire [1:0] cpu_speed,
    output reg        en_phi1,
    output reg        en_phi2
);

    // fx68k consumes alternating Phi1/Phi2 events, hence twice the displayed
    // CPU rate. The 48 MHz system domain can provide exact 24 MHz operation.
    localparam [15:0] QL_PHASE_STEP = 16'd20480; // 15 MHz phase events
    localparam [15:0] MHZ16_PHASE_STEP = 16'd43691; // 32.0002 MHz

    reg [15:0] phase_accum;
    reg phase_polarity;
    wire [15:0] phase_step = (cpu_speed == 2'd0) ? QL_PHASE_STEP :
                             MHZ16_PHASE_STEP;
    wire [16:0] phase_sum = {1'b0, phase_accum} +
                            {1'b0, phase_step};
    wire phase_tick = (cpu_speed >= 2'd2) ? 1'b1 : phase_sum[16];

    always @(posedge clk) begin
        if (reset) begin
            phase_accum <= 16'd0;
            phase_polarity <= 1'b0;
            en_phi1 <= 1'b0;
            en_phi2 <= 1'b0;
        end else begin
            phase_accum <= (cpu_speed >= 2'd2) ? 16'd0 :
                           phase_sum[15:0];
            en_phi1 <= phase_tick && !phase_polarity;
            en_phi2 <= phase_tick && phase_polarity;
            if (phase_tick)
                phase_polarity <= !phase_polarity;
        end
    end

endmodule
