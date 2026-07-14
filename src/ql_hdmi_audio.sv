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
    reg [1:0] audio_sync = 2'b00;

    always @(posedge clk_pixel) begin
        if (reset) begin
            audio_phase <= 32'd0;
            clk_audio <= 1'b0;
            audio_sync <= 2'b00;
        end else begin
            audio_sync <= {audio_sync[0], ql_audio};
            if (audio_phase >= PHASE_LIMIT) begin
                audio_phase <= audio_phase - PHASE_LIMIT;
                clk_audio <= ~clk_audio;
            end else begin
                audio_phase <= audio_phase + AUDIO_TOGGLE_RATE;
            end
        end
    end

    wire signed [15:0] mono_sample = reset ? 16'sd0 :
                                      audio_sync[1] ? AMPLITUDE : -AMPLITUDE;
    assign sample_left = mono_sample;
    assign sample_right = mono_sample;

endmodule
