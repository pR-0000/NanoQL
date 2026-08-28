module ql_video_scanout(
    input  wire        reset,
    input  wire        clk_bus,
    input  wire        clk_pixel,
    input  wire        visible,
    input  wire        ql_area,
    input  wire        ql_fetch_start,
    input  wire [7:0]  ql_fetch_y,
    input  wire [8:0]  ql_x,
    input  wire [7:0]  ql_y,
    input  wire        mode8,
    input  wire        blank,
    input  wire [21:0] frame_base,
    input  wire        frame_buffer_select,
    input  wire        flash_phase,

    output wire [21:0] addr,
    output wire        rd,
    input  wire        rd_ready,
    input  wire        din_valid,
    input  wire [15:0] din,

    output reg         fetch_underflow,
    output reg         scanout_buffer_select,
    output reg  [23:0] rgb
);

    // Both QL modes use exactly 64 16-bit words per scanline. Fetch one
    // complete line sequentially, then scan it out from this small buffer.
    reg [15:0] line_buffer [0:127];
    reg        fetch_active;
    // frame_base points to an immutable SDRAM snapshot. Adopt a newly
    // published snapshot only with source line zero and acknowledge it to the
    // copy engine, which then knows the former buffer can safely be reused.
    reg [21:0] fetch_frame_base;
    reg [1:0]  line_ready;
    reg        fetch_bank;
    reg [7:0]  fetch_y;
    reg [6:0]  issue_count;
    reg [6:0]  receive_count;

    // The HDMI scanout and QL/SDRAM domains deliberately use independent
    // clocks. A toggle transfers each line request to the bus domain while
    // the requested Y coordinate remains stable until the next request.
    reg        fetch_request_toggle;
    reg [7:0]  fetch_request_y;
    reg [1:0]  fetch_request_sync;
    reg        fetch_request_seen;

    always @(posedge clk_pixel) begin
        if (reset) begin
            fetch_request_toggle <= 1'b0;
            fetch_request_y <= 8'd0;
        end else if (ql_fetch_start) begin
            fetch_request_y <= ql_fetch_y;
            fetch_request_toggle <= ~fetch_request_toggle;
        end
    end

    wire [13:0] fetch_offset = {fetch_y, issue_count[5:0]};
    assign addr = fetch_frame_base + {8'd0, fetch_offset};
    assign rd = fetch_active && (issue_count < 7'd64);

    always @(posedge clk_bus) begin
        if (reset) begin
            fetch_active <= 1'b0;
            fetch_frame_base <= 22'h010000;
            scanout_buffer_select <= 1'b0;
            line_ready <= 2'b00;
            fetch_bank <= 1'b0;
            fetch_y <= 8'd0;
            issue_count <= 7'd0;
            receive_count <= 7'd0;
            fetch_request_sync <= 2'b00;
            fetch_request_seen <= 1'b0;
        end else begin
            fetch_request_sync <= {fetch_request_sync[0],
                                   fetch_request_toggle};

            if (!fetch_active &&
                (fetch_request_sync[1] != fetch_request_seen)) begin
                fetch_request_seen <= fetch_request_sync[1];
                fetch_active <= 1'b1;
                if (fetch_request_y == 8'd0) begin
                    fetch_frame_base <= frame_base;
                    scanout_buffer_select <= frame_buffer_select;
                end
                line_ready[fetch_request_y[0]] <= 1'b0;
                fetch_bank <= fetch_request_y[0];
                fetch_y <= fetch_request_y;
                issue_count <= 7'd0;
                receive_count <= 7'd0;
            end

            if (rd && rd_ready) begin
                issue_count <= issue_count + 7'd1;
                if (issue_count == 7'd63)
                    fetch_active <= 1'b0;
            end

            if (din_valid && (receive_count < 7'd64)) begin
                line_buffer[{fetch_bank, receive_count[5:0]}] <= din;
                receive_count <= receive_count + 7'd1;
                if (receive_count == 7'd63)
                    line_ready[fetch_bank] <= 1'b1;
            end

        end
    end

    reg [1:0] line_ready_pixel_meta;
    reg [1:0] line_ready_pixel;

    always @(posedge clk_pixel) begin
        if (reset) begin
            line_ready_pixel_meta <= 2'b00;
            line_ready_pixel <= 2'b00;
            fetch_underflow <= 1'b0;
        end else begin
            line_ready_pixel_meta <= line_ready;
            line_ready_pixel <= line_ready_pixel_meta;
            if (ql_fetch_start)
                fetch_underflow <= 1'b0;
            else if (ql_area && !line_ready_pixel[ql_y[0]])
                fetch_underflow <= 1'b1;
        end
    end

    reg visible_d;
    reg ql_area_d;
    reg mode8_meta;
    reg mode8_d;
    reg blank_meta;
    reg blank_d;
    reg flash_phase_meta;
    reg flash_phase_d;
    reg [8:0] ql_x_d;

    reg [15:0] video_word;

    // No reset here: this is the Gowin synchronous BSRAM read template.
    // The line is fully prefetched before ql_area becomes active.
    always @(posedge clk_pixel)
        video_word <= line_buffer[{ql_y[0], ql_x[8:3]}];

    wire [2:0] mode4_bit_index = ql_x_d[2:0];
    wire [1:0] mode4_code = {
        video_word[15 - mode4_bit_index],
        video_word[7 - mode4_bit_index]
    };

    wire [1:0] mode8_pixel_index = ql_x_d[2:1];
    wire [2:0] mode8_shift = {mode8_pixel_index, 1'b0};
    wire mode8_green = video_word[15 - mode8_shift];
    wire mode8_flash = video_word[14 - mode8_shift];
    wire mode8_red   = video_word[7 - mode8_shift];
    wire mode8_blue  = video_word[6 - mode8_shift];
    wire [2:0] mode8_code = {mode8_green, mode8_red, mode8_blue};

    reg mode8_flash_latched;
    reg [2:0] mode8_flash_color;

    function [23:0] ql_mode4_palette;
        input [1:0] code;
        begin
            case (code)
                2'b00: ql_mode4_palette = 24'h000000;
                2'b01: ql_mode4_palette = 24'hd02020;
                2'b10: ql_mode4_palette = 24'h20b040;
                default: ql_mode4_palette = 24'hffffff;
            endcase
        end
    endfunction

    function [23:0] ql_mode8_palette;
        input [2:0] code;
        begin
            case (code)
                3'b000: ql_mode8_palette = 24'h000000;
                3'b001: ql_mode8_palette = 24'h2040d0;
                3'b010: ql_mode8_palette = 24'hd02020;
                3'b011: ql_mode8_palette = 24'hd030d0;
                3'b100: ql_mode8_palette = 24'h20b040;
                3'b101: ql_mode8_palette = 24'h20c0c0;
                3'b110: ql_mode8_palette = 24'he0d040;
                default: ql_mode8_palette = 24'hffffff;
            endcase
        end
    endfunction

    wire [23:0] mode8_color = ql_mode8_palette(mode8_code);

    // In QL mode 8 the F bit toggles a latch; while that latch is active,
    // pixels flash to the color captured when the latch was toggled.
    // ql_x[0] is the second HDMI copy of each 256-pixel QL mode 8 pixel.
    always @(posedge clk_pixel) begin
        if (reset || !ql_area_d || !mode8_d) begin
            mode8_flash_latched <= 1'b0;
            mode8_flash_color <= 3'b000;
        end else if (ql_x_d[0] && mode8_flash) begin
            mode8_flash_latched <= ~mode8_flash_latched;
            mode8_flash_color <= mode8_code;
        end
    end

    always @(posedge clk_pixel) begin
        if (reset) begin
            visible_d <= 1'b0;
            ql_area_d <= 1'b0;
            ql_x_d <= 9'd0;
            mode8_meta <= 1'b0;
            mode8_d <= 1'b0;
            blank_meta <= 1'b0;
            blank_d <= 1'b0;
            flash_phase_meta <= 1'b0;
            flash_phase_d <= 1'b0;
        end else begin
            visible_d <= visible;
            ql_area_d <= ql_area;
            ql_x_d <= ql_x;
            mode8_meta <= mode8;
            mode8_d <= mode8_meta;
            blank_meta <= blank;
            blank_d <= blank_meta;
            flash_phase_meta <= flash_phase;
            flash_phase_d <= flash_phase_meta;
        end
    end

    always @* begin
        if (!visible_d) begin
            rgb = 24'h000000;
        end else if (!ql_area_d) begin
            rgb = 24'h000000;
        end else if (blank_d) begin
            rgb = 24'h000000;
        end else if (!line_ready_pixel[ql_y[0]]) begin
            rgb = 24'hff00ff;
        end else if (mode8_d) begin
            rgb = (mode8_flash_latched && flash_phase_d) ?
                  ql_mode8_palette(mode8_flash_color) : mode8_color;
        end else begin
            rgb = ql_mode4_palette(mode4_code);
        end
    end

endmodule


