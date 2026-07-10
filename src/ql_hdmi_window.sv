module ql_hdmi_window(
    input  wire [10:0] x,
    input  wire [9:0]  y,

    output wire        visible,
    output wire        ql_area,
    output wire        ql_fetch_start,
    output wire [7:0]  ql_fetch_y,
    output wire [8:0]  ql_x,
    output wire [7:0]  ql_y
);

    localparam [10:0] VISIBLE_W = 11'd720;
    localparam [9:0]  VISIBLE_H = 10'd576;

    assign visible = (x < VISIBLE_W) && (y < VISIBLE_H);
    assign ql_area = visible;

    // Present the 512x256 QL framebuffer as a 4:3 image filling the PAL
    // frame. A virtual 768x576 image is cropped symmetrically to 720x576:
    // 16 source pixels are omitted on each horizontal edge, with no vertical
    // crop. Constant-ratio nearest-neighbour scaling keeps the logic small.
    wire [11:0] virtual_x = {1'b0, x} + 12'd24;
    wire [12:0] scaled_x = {virtual_x, 1'b0};
    wire [11:0] scaled_y = {y, 2'b00};
    wire [7:0] source_y = scaled_y / 12'd9;

    wire [10:0] next_y = {1'b0, y} + 11'd1;
    wire [12:0] next_scaled_y = {next_y, 2'b00};
    wire [7:0] next_source_y = next_scaled_y / 13'd9;

    assign ql_x = scaled_x / 13'd3;
    assign ql_y = source_y;

    // Fetch a source line only before its first repeated HDMI line. Source
    // line zero is prefetched during the final blanking line of each frame.
    assign ql_fetch_start = (x == 11'd0) &&
                            ((y == 10'd625) ||
                             ((y < VISIBLE_H - 10'd1) &&
                              (next_source_y != source_y)));
    assign ql_fetch_y = (y == 10'd625) ? 8'd0 : next_source_y;

endmodule
