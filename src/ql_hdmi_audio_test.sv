module ql_hdmi_audio #(
    parameter integer PIXEL_CLOCK = 74_250_000,
    parameter integer AUDIO_RATE = 48_000,
    parameter signed [15:0] AMPLITUDE = 16'sh3000
)(
    input  wire        clk_pixel,
    input  wire        reset,
    input  wire        ql_audio,
    output reg         clk_audio,
    output wire [15:0] sample_left,
    output wire [15:0] sample_right
);

    localparam integer AUDIO_TOGGLE_RATE = AUDIO_RATE * 2;
    localparam integer PHASE_LIMIT = PIXEL_CLOCK - AUDIO_TOGGLE_RATE;

    reg [31:0] audio_phase = 32'd0;
    reg [5:0] sample_count = 6'd0;
    reg tone = 1'b0;

    always @(posedge clk_pixel) begin
        if (reset) begin
            audio_phase <= 32'd0;
            clk_audio <= 1'b0;
            sample_count <= 6'd0;
            tone <= 1'b0;
        end else if (audio_phase >= PHASE_LIMIT) begin
            audio_phase <= audio_phase - PHASE_LIMIT;
            clk_audio <= ~clk_audio;
            if (!clk_audio) begin
                if (sample_count == 6'd23) begin
                    sample_count <= 6'd0;
                    tone <= ~tone;
                end else begin
                    sample_count <= sample_count + 6'd1;
                end
            end
        end else begin
            audio_phase <= audio_phase + AUDIO_TOGGLE_RATE;
        end
    end

    wire signed [15:0] mono_sample = reset ? 16'sd0 :
                                      tone ? AMPLITUDE : -AMPLITUDE;
    assign sample_left = mono_sample;
    assign sample_right = mono_sample;

    wire unused_ql_audio = ql_audio;

endmodule
