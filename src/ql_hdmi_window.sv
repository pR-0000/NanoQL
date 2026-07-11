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
    localparam [10:0] QL_LEFT = 11'd104;
    localparam [10:0] QL_RIGHT = 11'd616;
    localparam [9:0]  QL_TOP = 10'd32;
    localparam [9:0]  QL_BOTTOM = 10'd544;

    assign visible = (x < VISIBLE_W) && (y < VISIBLE_H);
    assign ql_area = visible &&
                     (x >= QL_LEFT) && (x < QL_RIGHT) &&
                     (y >= QL_TOP) && (y < QL_BOTTOM);

    // Integer scaling keeps every source pixel exactly the same size. The
    // complete 512x256 framebuffer becomes a centered 512x512 image: one
    // HDMI sample horizontally and two HDMI lines vertically per QL pixel.
    wire [10:0] content_x = (x < QL_LEFT) ? 11'd0 :
                            (x >= QL_RIGHT) ? 11'd511 : x - QL_LEFT;
    wire [9:0] content_y = (y < QL_TOP) ? 10'd0 :
                           (y >= QL_BOTTOM) ? 10'd511 : y - QL_TOP;
    wire [7:0] source_y = content_y[8:1];

    wire [10:0] next_y = {1'b0, y} + 11'd1;
    wire [10:0] next_content_y = next_y - {1'b0, QL_TOP};
    wire [7:0] next_source_y = next_content_y[8:1];

    assign ql_x = content_x[8:0];
    assign ql_y = source_y;

    // Fetch a source line only before its first repeated HDMI line. Source
    // line zero is prefetched during the final blanking line of each frame.
    assign ql_fetch_start = (x == 11'd0) &&
                            ((y == 10'd625) ||
                             ((y >= QL_TOP) &&
                              (y < QL_BOTTOM - 10'd1) &&
                              (next_source_y != source_y)));
    assign ql_fetch_y = (y == 10'd625) ? 8'd0 : next_source_y;

endmodule
