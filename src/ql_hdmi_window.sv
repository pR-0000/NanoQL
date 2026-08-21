module ql_hdmi_window(
    input  wire        clk,
    input  wire        reset,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [2:0]  video_mode,

    output reg         visible,
    output reg         ql_area,
    output reg         ql_fetch_start,
    output reg  [7:0]  ql_fetch_y,
    output reg  [8:0]  ql_x,
    output reg  [7:0]  ql_y
);

    localparam [9:0] VISIBLE_H = 10'd720;

    // The original QL's pixels are not square. On a correctly adjusted CRT,
    // the complete active picture is approximately 4.4:3 rather than 4:3.
    // The 50/60 Hz variants use identical geometry; video_mode 3..5 only
    // changes the HDMI frame timing.
    reg [10:0] ql_left;
    reg [10:0] ql_width;
    reg [9:0] ql_top;
    reg [9:0] ql_height;

    always @* begin
        case (video_mode)
            3'd0, 3'd3: begin
                // Sharp gives every QL source column exactly two HDMI
                // pixels.  The vertical size retains the corrected QL pixel
                // aspect ratio; its fractional scaling is much less visible
                // than irregular character and stipple widths.
                ql_left = 11'd128;
                ql_width = 11'd1024;
                ql_top = 10'd11;
                ql_height = 10'd698;
            end
            3'd1, 3'd4: begin
                ql_left = 11'd218;
                ql_width = 11'd844;
                ql_top = 10'd72;
                ql_height = 10'd576;
            end
            default: begin
                // Fit keeps the complete QL raster away from the outermost
                // HDMI lines, which some televisions still hide as overscan.
                // 990/675 is exactly 4.4:3 and leaves an overscan-safe frame
                // of 22/23 lines plus 145 pixels on both horizontal sides.
                ql_left = 11'd145;
                ql_width = 11'd990;
                ql_top = 10'd22;
                ql_height = 10'd675;
            end
        endcase
    end

    wire [10:0] ql_right = ql_left + ql_width;
    wire [9:0] ql_bottom = ql_top + ql_height;
    wire in_ql_area = (x >= ql_left) && (x < ql_right) &&
                      (y >= ql_top) && (y < ql_bottom);

    // Fixed-ratio nearest-neighbour scalers. Accumulating the 512x256 source
    // dimensions avoids dividers and gives a deterministic repetition phase.
    reg [10:0] horizontal_phase;
    wire [11:0] horizontal_sum = {1'b0, horizontal_phase} + 12'd512;
    wire advance_x = horizontal_sum >= {1'b0, ql_width};

    reg [9:0] vertical_phase;
    wire [10:0] vertical_sum = {1'b0, vertical_phase} + 11'd256;
    wire advance_y = vertical_sum >= {1'b0, ql_height};
    wire [9:0] phase_after_y = advance_y ?
                               vertical_sum - {1'b0, ql_height} :
                               vertical_sum[9:0];
    wire [10:0] next_vertical_sum = {1'b0, phase_after_y} + 11'd256;
    wire advance_next_y = next_vertical_sum >= {1'b0, ql_height};
    wire [7:0] source_after_y = ql_y + {7'd0, advance_y};

    always @(posedge clk) begin
        if (reset) begin
            visible <= 1'b0;
            ql_area <= 1'b0;
            ql_fetch_start <= 1'b0;
            ql_fetch_y <= 8'd0;
            ql_x <= 9'd0;
            ql_y <= 8'd0;
            horizontal_phase <= 11'd0;
            vertical_phase <= 10'd0;
        end else begin
            visible <= (x < 11'd1280) && (y < VISIBLE_H);
            ql_area <= in_ql_area;

            if (x == 11'd0) begin
                if (y == ql_top) begin
                    ql_y <= 8'd0;
                    vertical_phase <= 10'd0;
                end else if ((y > ql_top) && (y < ql_bottom)) begin
                    ql_y <= source_after_y;
                    vertical_phase <= phase_after_y;
                end
            end

            // Fetch source line zero during the final blanking line. For all
            // other lines, request a line one complete HDMI row before it is
            // first displayed, leaving ample time for the SDRAM burst.
            ql_fetch_start <= ((x == 11'd0) && (y == 10'd749)) ||
                              ((x == 11'd0) &&
                               (y >= ql_top) &&
                               (y < ql_bottom - 10'd1) &&
                               ((y == ql_top) ?
                                (11'd256 >= {1'b0, ql_height}) :
                                advance_next_y));
            ql_fetch_y <= ((x == 11'd0) && (y == 10'd749)) ?
                          8'd0 :
                          ((y == ql_top) ? 8'd1 : source_after_y + 8'd1);

            if (x == ql_left) begin
                ql_x <= 9'd0;
                horizontal_phase <= 11'd0;
            end else if (in_ql_area) begin
                horizontal_phase <= advance_x ?
                                    horizontal_sum - {1'b0, ql_width} :
                                    horizontal_sum[10:0];
                if (advance_x && (ql_x != 9'd511))
                    ql_x <= ql_x + 9'd1;
            end
        end
    end

endmodule
