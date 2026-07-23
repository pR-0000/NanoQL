module ql_hdmi_audio #(
    parameter integer PIXEL_CLOCK = 74_250_000,
    parameter integer AUDIO_RATE = 48_000,
    parameter signed [15:0] AMPLITUDE = 16'sh3000
)(
    input  wire        clk_pixel,
    input  wire        reset,
    input  wire        ql_audio,
    input  wire [9:0]  qsound_audio,
    input  wire        qsound_audio_toggle,
    output reg         clk_audio,
    output wire [15:0] sample_left,
    output wire [15:0] sample_right
);

    localparam integer AUDIO_TOGGLE_RATE = AUDIO_RATE * 2;
    localparam integer PHASE_LIMIT = PIXEL_CLOCK - AUDIO_TOGGLE_RATE;

    reg [31:0] audio_phase = 32'd0;
    reg [1:0] audio_sync = 2'b00;
    reg [9:0] qsound_data_sync_1 = 10'd0;
    reg [9:0] qsound_data_sync_2 = 10'd0;
    reg [2:0] qsound_toggle_sync = 3'd0;
    reg qsound_toggle_seen = 1'b0;
    reg [9:0] qsound_sample_hold = 10'd0;

    always @(posedge clk_pixel) begin
        if (reset) begin
            audio_phase <= 32'd0;
            clk_audio <= 1'b0;
            audio_sync <= 2'b00;
            qsound_data_sync_1 <= 10'd0;
            qsound_data_sync_2 <= 10'd0;
            qsound_toggle_sync <= 3'd0;
            qsound_toggle_seen <= 1'b0;
            qsound_sample_hold <= 10'd0;
        end else begin
            audio_sync <= {audio_sync[0], ql_audio};
            qsound_data_sync_1 <= qsound_audio;
            qsound_data_sync_2 <= qsound_data_sync_1;
            qsound_toggle_sync <= {qsound_toggle_sync[1:0],
                                   qsound_audio_toggle};
            if (qsound_toggle_sync[2] != qsound_toggle_seen) begin
                qsound_sample_hold <= qsound_data_sync_2;
                qsound_toggle_seen <= qsound_toggle_sync[2];
            end
            if (audio_phase >= PHASE_LIMIT) begin
                audio_phase <= audio_phase - PHASE_LIMIT;
                clk_audio <= ~clk_audio;
            end else begin
                audio_phase <= audio_phase + AUDIO_TOGGLE_RATE;
            end
        end
    end

    wire signed [16:0] ql_sample = audio_sync[1] ? AMPLITUDE : -AMPLITUDE;
    // The physical AY output is unipolar. Preserve that waveform here and
    // leave DC blocking to the HDMI sink's analogue output stage; tracking
    // its moving average digitally causes audible low-frequency pumping.
    wire signed [17:0] qsound_sample =
        $signed({1'b0, qsound_sample_hold, 3'b000});
    wire signed [18:0] mixed_sample = ql_sample + qsound_sample;
    wire signed [15:0] mono_sample = reset ? 16'sd0 :
        (mixed_sample > 19'sd32767) ? 16'sh7fff :
        (mixed_sample < -19'sd32768) ? 16'sh8000 :
                                      mixed_sample[15:0];
    assign sample_left = mono_sample;
    assign sample_right = mono_sample;

endmodule
