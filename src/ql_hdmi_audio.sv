module ql_hdmi_audio #(
    parameter integer PIXEL_CLOCK = 74_250_000,
    parameter integer AUDIO_RATE = 48_000,
    parameter signed [15:0] AMPLITUDE = 16'sh3000
)(
    input  wire        clk_pixel,
    input  wire        reset,
    input  wire        ql_audio,
    input  wire [9:0]  qsound_audio,
    output reg         clk_audio,
    output wire [15:0] sample_left,
    output wire [15:0] sample_right
);

    localparam integer AUDIO_TOGGLE_RATE = AUDIO_RATE * 2;
    localparam integer PHASE_LIMIT = PIXEL_CLOCK - AUDIO_TOGGLE_RATE;

    reg [31:0] audio_phase = 32'd0;
    reg [1:0] audio_sync = 2'b00;
    reg [9:0] qsound_sync_1 = 10'd0;
    reg [9:0] qsound_sync_2 = 10'd0;
    reg signed [17:0] qsound_dc = 18'sd0;

    always @(posedge clk_pixel) begin
        if (reset) begin
            audio_phase <= 32'd0;
            clk_audio <= 1'b0;
            audio_sync <= 2'b00;
            qsound_sync_1 <= 10'd0;
            qsound_sync_2 <= 10'd0;
            qsound_dc <= 18'sd0;
        end else begin
            audio_sync <= {audio_sync[0], ql_audio};
            qsound_sync_1 <= qsound_audio;
            qsound_sync_2 <= qsound_sync_1;
            if (audio_phase >= PHASE_LIMIT) begin
                audio_phase <= audio_phase - PHASE_LIMIT;
                clk_audio <= ~clk_audio;
                if (!clk_audio)
                    qsound_dc <= qsound_dc +
                        (($signed({1'b0, qsound_sync_2, 3'b000}) -
                          qsound_dc) >>> 8);
            end else begin
                audio_phase <= audio_phase + AUDIO_TOGGLE_RATE;
            end
        end
    end

    wire signed [16:0] ql_sample = audio_sync[1] ? AMPLITUDE : -AMPLITUDE;
    wire signed [17:0] qsound_sample =
        $signed({1'b0, qsound_sync_2, 3'b000}) - qsound_dc;
    wire signed [18:0] mixed_sample = ql_sample + qsound_sample;
    wire signed [15:0] mono_sample = reset ? 16'sd0 :
        (mixed_sample > 19'sd32767) ? 16'sh7fff :
        (mixed_sample < -19'sd32768) ? 16'sh8000 :
                                      mixed_sample[15:0];
    assign sample_left = mono_sample;
    assign sample_right = mono_sample;

endmodule
