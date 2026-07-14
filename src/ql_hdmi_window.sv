module ql_hdmi_window(
    input  wire        clk,
    input  wire        reset,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [1:0]  aspect_mode,

    output reg         visible,
    output reg         ql_area,
    output reg         ql_fetch_start,
    output reg  [7:0]  ql_fetch_y,
    output reg  [8:0]  ql_x,
    output reg  [7:0]  ql_y
);

    localparam [9:0]  VISIBLE_H = 10'd720;
    localparam [9:0]  QL_TOP = 10'd104;
    localparam [9:0]  QL_BOTTOM = 10'd616;
    localparam [9:0]  QL_WIDE_TOP = 10'd129;
    localparam [9:0]  QL_WIDE_BOTTOM = 10'd591;

    reg [10:0] ql_left;
    reg [10:0] ql_width;
    always @* begin
        case (aspect_mode)
            // Monitor is exact 2x integer scaling: each QL framebuffer sample
            // becomes a uniform 2x2 block in square-pixel 720p output.
            2'd0: begin
                ql_left = 11'd128;
                ql_width = 11'd1024;
            end
            // TV adds the slight horizontal correction expected on a modern
            // 16:9 panel while retaining the complete 512-sample QL line.
            2'd1: begin
                ql_left = 11'd64;
                ql_width = 11'd1152;
            end
            2'd2: begin
                ql_left = 11'd96;
                ql_width = 11'd1088;
            end
            default: begin
                ql_left = 11'd40;
                ql_width = 11'd1200;
            end
        endcase
    end
    wire [10:0] ql_right = ql_left + ql_width;

    // Wide +30% keeps a 40-pixel safety margin on both sides. A 1200x462
    // window gives a 1.299 geometry correction while preserving every one
    // of the 512x256 QL samples.
    wire [9:0] ql_top = (aspect_mode == 2'd3) ? QL_WIDE_TOP : QL_TOP;
    wire [9:0] ql_bottom = (aspect_mode == 2'd3) ?
                           QL_WIDE_BOTTOM : QL_BOTTOM;

    wire in_ql_area = (x >= ql_left) && (x < ql_right) &&
                      (y >= ql_top) && (y < ql_bottom);
    wire [9:0] content_y = y - ql_top;
    wire [7:0] source_y = content_y[8:1];

    wire [10:0] next_y = {1'b0, y} + 11'd1;
    wire [10:0] next_content_y = next_y - {1'b0, ql_top};
    wire [7:0] next_source_y = next_content_y[8:1];

    reg [7:0] vertical_phase;
    wire [8:0] vertical_phase_sum = {1'b0, vertical_phase} + 9'd128;
    wire advance_wide_y = vertical_phase_sum >= 9'd231;
    wire [7:0] vertical_phase_current = advance_wide_y ?
                                      vertical_phase_sum - 9'd231 :
                                      vertical_phase_sum[7:0];
    wire [8:0] vertical_phase_next_sum =
               {1'b0, vertical_phase_current} + 9'd128;
    wire advance_wide_y_next = vertical_phase_next_sum >= 9'd231;

    reg [6:0] horizontal_phase;
    wire advance_tv = (horizontal_phase == 7'd2) ||
                      (horizontal_phase == 7'd4) ||
                      (horizontal_phase == 7'd6) ||
                      (horizontal_phase == 7'd8);
    wire advance_wide_6 = advance_tv ||
                          (horizontal_phase == 7'd10) ||
                          (horizontal_phase == 7'd12) ||
                          (horizontal_phase == 7'd14) ||
                          (horizontal_phase == 7'd16);
    wire [7:0] horizontal_wide_sum =
               {1'b0, horizontal_phase} + 8'd32;
    wire advance_wide_30 = horizontal_wide_sum >= 8'd75;

    // The fractional modes use a Bresenham-style phase counter. This avoids
    // a long divider path and makes the repetition pattern deterministic.
    always @(posedge clk) begin
        if (reset) begin
            visible <= 1'b0;
            ql_area <= 1'b0;
            ql_fetch_start <= 1'b0;
            ql_fetch_y <= 8'd0;
            ql_x <= 9'd0;
            ql_y <= 8'd0;
            horizontal_phase <= 7'd0;
            vertical_phase <= 8'd0;
        end else begin
            visible <= (x < 11'd1280) && (y < VISIBLE_H);
            ql_area <= in_ql_area;

            if (aspect_mode != 2'd3) begin
                ql_y <= source_y;
                vertical_phase <= 8'd0;
            end else if (x == 11'd0) begin
                if (y == ql_top) begin
                    ql_y <= 8'd0;
                    vertical_phase <= 8'd0;
                end else if ((y > ql_top) && (y < ql_bottom)) begin
                    if (advance_wide_y) begin
                        ql_y <= ql_y + 8'd1;
                        vertical_phase <= vertical_phase_sum - 9'd231;
                    end else begin
                        vertical_phase <= vertical_phase_sum[7:0];
                    end
                end
            end

            // Request the next source line at the start of the preceding
            // display line. This leaves a complete 26.7 us HDMI line for the
            // SDRAM fetch, including in the fractional Wide +30% mode.
            ql_fetch_start <= ((x == 11'd0) && (y == 10'd749)) ||
                              ((x == 11'd0) &&
                               (y >= ql_top) &&
                               (y < ql_bottom - 10'd1) &&
                               ((aspect_mode == 2'd3) ?
                                ((y != ql_top) &&
                                 advance_wide_y_next) :
                                (next_source_y != source_y)));
            ql_fetch_y <= ((x == 11'd0) && (y == 10'd749)) ?
                          8'd0 :
                          ((aspect_mode == 2'd3) ?
                           ql_y + {7'd0, advance_wide_y} + 8'd1 :
                           next_source_y);

            if (x == ql_left) begin
                ql_x <= 9'd0;
                horizontal_phase <= 7'd0;
            end else if (in_ql_area) begin
                case (aspect_mode)
                    2'd0: begin
                        horizontal_phase <= {6'd0, horizontal_phase[0]} + 7'd1;
                        if (horizontal_phase[0] && (ql_x != 9'd511))
                            ql_x <= ql_x + 9'd1;
                    end
                    2'd1: begin
                        horizontal_phase <= horizontal_phase == 7'd8 ?
                                            7'd0 : horizontal_phase + 7'd1;
                        if (advance_tv && (ql_x != 9'd511))
                            ql_x <= ql_x + 9'd1;
                    end
                    2'd2: begin
                        horizontal_phase <= horizontal_phase == 7'd16 ?
                                            7'd0 : horizontal_phase + 7'd1;
                        if (advance_wide_6 && (ql_x != 9'd511))
                            ql_x <= ql_x + 9'd1;
                    end
                    default: begin
                        horizontal_phase <= advance_wide_30 ?
                                            horizontal_wide_sum - 8'd75 :
                                            horizontal_wide_sum[6:0];
                        if (advance_wide_30 && (ql_x != 9'd511))
                            ql_x <= ql_x + 9'd1;
                    end
                endcase
            end
        end
    end

endmodule
