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

    // Sinclair QL active display used by zx8301.v: 512x256.
    localparam [10:0] QL_X0 = 11'd104;  // (720 - 512) / 2
    localparam [9:0]  QL_Y0 = 10'd160;  // (576 - 256) / 2
    localparam [10:0] QL_W  = 11'd512;
    localparam [9:0]  QL_H  = 10'd256;

    assign visible = (x < VISIBLE_W) && (y < VISIBLE_H);
    assign ql_area = (x >= QL_X0) && (x < QL_X0 + QL_W) &&
                     (y >= QL_Y0) && (y < QL_Y0 + QL_H);

    // Prefetch each line one HDMI line early. The SDRAM controller handles
    // one word at a time, so the next line is loaded while this line runs.
    assign ql_fetch_start = (x == 11'd0) &&
                            (y >= QL_Y0 - 10'd1) &&
                            (y < QL_Y0 + QL_H - 10'd1);
    assign ql_fetch_y = y[7:0] - (QL_Y0[7:0] - 8'd1);

    assign ql_x = x[8:0] - QL_X0[8:0];
    assign ql_y = y[7:0] - QL_Y0[7:0];

endmodule
