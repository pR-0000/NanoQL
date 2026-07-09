module ql_native_timing_probe(
    input  wire       clk_pixel,
    input  wire       reset,
    input  wire       ntsc,

    output reg        ce_ql,
    output reg [9:0]  h_cnt,
    output reg [9:0]  v_cnt,
    output reg        hs,
    output reg        vs,
    output wire       active,
    output reg        vblank,
    output reg        frame_pulse
);

    // PAL/NTSC timing values copied from the structure of mist-devel/ql/zx8301.v.
    localparam [9:0] H_VISIBLE = 10'd512;
    localparam [9:0] V_VISIBLE = 10'd256;

    localparam [9:0] PAL_HFP = 10'd27;
    localparam [9:0] PAL_HSW = 10'd50;
    localparam [9:0] PAL_HBP = 10'd83;
    localparam [9:0] PAL_VFP = 10'd18;
    localparam [9:0] PAL_VSW = 10'd6;
    localparam [9:0] PAL_VBP = 10'd33;

    localparam [9:0] NTSC_HFP = 10'd34;
    localparam [9:0] NTSC_HSW = 10'd64;
    localparam [9:0] NTSC_HBP = 10'd54;
    localparam [9:0] NTSC_VFP = 10'd2;
    localparam [9:0] NTSC_VSW = 10'd2;
    localparam [9:0] NTSC_VBP = 10'd2;

    wire [9:0] hfp = ntsc ? NTSC_HFP : PAL_HFP;
    wire [9:0] hsw = ntsc ? NTSC_HSW : PAL_HSW;
    wire [9:0] hbp = ntsc ? NTSC_HBP : PAL_HBP;
    wire [9:0] vfp = ntsc ? NTSC_VFP : PAL_VFP;
    wire [9:0] vsw = ntsc ? NTSC_VSW : PAL_VSW;
    wire [9:0] vbp = ntsc ? NTSC_VBP : PAL_VBP;

    wire [9:0] h_total = H_VISIBLE + hfp + hsw + hbp;
    wire [9:0] v_total = V_VISIBLE + vfp + vsw + vbp;

    assign active = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    reg [1:0] ce_div;

    always @(posedge clk_pixel) begin
        if (reset) begin
            ce_div <= 2'd0;
            ce_ql <= 1'b0;
        end else begin
            if (ce_div == 2'd2) begin
                ce_div <= 2'd0;
                ce_ql <= 1'b1;
            end else begin
                ce_div <= ce_div + 2'd1;
                ce_ql <= 1'b0;
            end
        end
    end

    always @(posedge clk_pixel) begin
        frame_pulse <= 1'b0;

        if (reset) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
            hs <= 1'b1;
            vs <= 1'b0;
            vblank <= 1'b0;
        end else if (ce_ql) begin
            if (h_cnt == h_total - 10'd1) begin
                h_cnt <= 10'd0;

                if (v_cnt == v_total - 10'd1) begin
                    v_cnt <= 10'd0;
                    frame_pulse <= 1'b1;
                end else begin
                    v_cnt <= v_cnt + 10'd1;
                end
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end

            // The original zx8301 uses negative hsync and positive vsync.
            hs <= !((h_cnt >= H_VISIBLE + hfp) && (h_cnt < H_VISIBLE + hfp + hsw));
            vs <=  ((v_cnt >= V_VISIBLE + vfp) && (v_cnt < V_VISIBLE + vfp + vsw));
            vblank <= (v_cnt >= V_VISIBLE);
        end
    end

endmodule
