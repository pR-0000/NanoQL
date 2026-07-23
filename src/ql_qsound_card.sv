module ql_qsound_card (
    input  wire        clk,
    input  wire        reset,
    input  wire        core_reset,
    input  wire        ql_ce_10m5,

    input  wire        image_mounted,
    input  wire [63:0] image_size,
    output reg         sd_read_start,
    output reg  [31:0] sd_sector,
    input  wire        sd_busy,
    input  wire        sd_done,
    input  wire        sd_byte_valid,
    input  wire [8:0]  sd_byte_addr,
    input  wire [7:0]  sd_byte,

    input  wire        bus_req,
    input  wire        bus_we,
    input  wire [21:0] bus_addr,
    input  wire [1:0]  bus_ds,
    input  wire [15:0] bus_wdata,
    output wire        bus_ready,
    output reg         bus_data_valid,
    output reg  [15:0] bus_data,
    output reg         bus_write_done,

    output reg  [9:0]  audio,
    output reg         audio_toggle,
    output reg         loading,
    output reg         loaded,
    output reg         failed
);

    localparam [2:0] LOAD_IDLE     = 3'd0;
    localparam [2:0] LOAD_VALIDATE = 3'd1;
    localparam [2:0] LOAD_REQUEST  = 3'd2;
    localparam [2:0] LOAD_WAIT     = 3'd3;
    localparam [2:0] LOAD_DONE     = 3'd4;
    localparam [2:0] LOAD_FAILED   = 3'd5;

    localparam [21:0] ROM_FIRST_WORD = 22'h060000;
    localparam [21:0] ROM_LAST_WORD  = 22'h060fff;

    reg [2:0] load_state;
    reg [4:0] sector_index;
    reg [9:0] sector_byte_count;
    reg [7:0] high_byte;
    reg mount_pending;
    reg [15:0] rom [0:4095];

    wire valid_image_size = image_size == 64'd8192;

    always @(posedge clk) begin
        if (reset) begin
            load_state <= LOAD_IDLE;
            sector_index <= 5'd0;
            sector_byte_count <= 10'd0;
            high_byte <= 8'd0;
            mount_pending <= 1'b0;
            sd_read_start <= 1'b0;
            sd_sector <= 32'd0;
            loading <= 1'b0;
            loaded <= 1'b0;
            failed <= 1'b0;
        end else begin
            if (image_mounted)
                mount_pending <= 1'b1;

            if (sd_byte_valid) begin
                sector_byte_count <= sector_byte_count + 10'd1;
                if (!sd_byte_addr[0])
                    high_byte <= sd_byte;
                else
                    rom[{sector_index[3:0], sd_byte_addr[8:1]}] <=
                        {high_byte, sd_byte};
            end

            case (load_state)
                LOAD_IDLE: begin
                    sd_read_start <= 1'b0;
                    loading <= 1'b0;
                    if (mount_pending || image_mounted) begin
                        mount_pending <= 1'b0;
                        loaded <= 1'b0;
                        failed <= 1'b0;
                        load_state <= LOAD_VALIDATE;
                    end
                end

                LOAD_VALIDATE: begin
                    if (image_size == 64'd0) begin
                        loading <= 1'b0;
                        loaded <= 1'b0;
                        failed <= 1'b0;
                        load_state <= LOAD_IDLE;
                    end else if (valid_image_size) begin
                        sector_index <= 5'd0;
                        sector_byte_count <= 10'd0;
                        sd_sector <= 32'd0;
                        loading <= 1'b1;
                        load_state <= LOAD_REQUEST;
                    end else begin
                        failed <= 1'b1;
                        load_state <= LOAD_FAILED;
                    end
                end

                LOAD_REQUEST: begin
                    sd_read_start <= 1'b1;
                    load_state <= LOAD_WAIT;
                end

                LOAD_WAIT: begin
                    if (sd_busy)
                        sd_read_start <= 1'b0;
                    if (sd_done) begin
                        sd_read_start <= 1'b0;
                        if (sector_byte_count != 10'd512) begin
                            failed <= 1'b1;
                            load_state <= LOAD_FAILED;
                        end else if (sector_index == 5'd15) begin
                            load_state <= LOAD_DONE;
                        end else begin
                            sector_index <= sector_index + 5'd1;
                            sector_byte_count <= 10'd0;
                            sd_sector <= sd_sector + 32'd1;
                            load_state <= LOAD_REQUEST;
                        end
                    end
                end

                LOAD_DONE: begin
                    loading <= 1'b0;
                    loaded <= 1'b1;
                    if (image_mounted) begin
                        mount_pending <= 1'b0;
                        loaded <= 1'b0;
                        load_state <= LOAD_VALIDATE;
                    end
                end

                default: begin
                    sd_read_start <= 1'b0;
                    loading <= 1'b0;
                    loaded <= 1'b0;
                    if (image_mounted) begin
                        mount_pending <= 1'b0;
                        failed <= 1'b0;
                        load_state <= LOAD_VALIDATE;
                    end
                end
            endcase
        end
    end

    wire rom_selected = (bus_addr >= ROM_FIRST_WORD) &&
                        (bus_addr <= ROM_LAST_WORD);
    wire pia_selected = !rom_selected;
    wire [1:0] pia_rs = {
        bus_addr[0],
        bus_ds[1] && !bus_ds[0]
    };
    wire [7:0] bus_write_byte = !bus_ds[1] ? bus_wdata[15:8] :
                                                   bus_wdata[7:0];

    reg bus_pending;
    reg pending_rom;
    reg [11:0] pending_rom_addr;
    reg [7:0] pending_pia_data;
    reg pia_write;
    reg [1:0] pia_write_rs;
    reg [7:0] pia_write_data;
    wire [7:0] pia_data;
    wire [7:0] pia_port_a;
    wire [7:0] pia_port_b;
    wire [7:0] psg_data_out;
    wire psg_bdir = pia_port_b[2];
    wire psg_bc1 = pia_port_b[0];
    wire psg_read = !psg_bdir && psg_bc1;

    assign bus_ready = !bus_pending;

    ql_mc6821_pia pia (
        .clk(clk),
        .reset(core_reset || !loaded),
        .write(pia_write),
        .rs(pia_write_rs),
        .data_in(pia_write_data),
        .data_out(pia_data),
        .port_a_in(psg_read ? psg_data_out : 8'hff),
        .port_b_in(8'h00),
        .port_a_pins(pia_port_a),
        .port_b_pins(pia_port_b)
    );

    always @(posedge clk) begin
        if (reset || core_reset || !loaded) begin
            bus_pending <= 1'b0;
            pending_rom <= 1'b0;
            pending_rom_addr <= 12'd0;
            pending_pia_data <= 8'd0;
            pia_write <= 1'b0;
            pia_write_rs <= 2'd0;
            pia_write_data <= 8'd0;
            bus_data_valid <= 1'b0;
            bus_data <= 16'hffff;
            bus_write_done <= 1'b0;
        end else begin
            pia_write <= 1'b0;
            bus_data_valid <= 1'b0;
            bus_write_done <= 1'b0;

            if (bus_pending) begin
                bus_data <= pending_rom ? rom[pending_rom_addr] :
                                          {pending_pia_data, pending_pia_data};
                bus_data_valid <= 1'b1;
                bus_pending <= 1'b0;
            end else if (bus_req) begin
                if (bus_we) begin
                    if (pia_selected) begin
                        pia_write <= 1'b1;
                        pia_write_rs <= pia_rs;
                        pia_write_data <= bus_write_byte;
                    end
                    bus_write_done <= 1'b1;
                end else begin
                    bus_pending <= 1'b1;
                    pending_rom <= rom_selected;
                    pending_rom_addr <= bus_addr[11:0];
                    pending_pia_data <= pia_data;
                end
            end
        end
    end

    reg [3:0] psg_clock_divider;
    reg psg_clock_enable;
    wire [9:0] psg_sound;
    wire psg_sample;
    wire psg_reset_n = !(core_reset || !loaded);

    always @(posedge clk) begin
        if (!psg_reset_n) begin
            psg_clock_divider <= 4'd0;
            psg_clock_enable <= 1'b0;
        end else begin
            psg_clock_enable <= 1'b0;
            if (ql_ce_10m5) begin
                if (psg_clock_divider == 4'd13) begin
                    psg_clock_divider <= 4'd0;
                    psg_clock_enable <= 1'b1;
                end else begin
                    psg_clock_divider <= psg_clock_divider + 4'd1;
                end
            end
        end
    end

    jt49_bus #(
        .AY8910(1)
    ) psg (
        .rst_n(psg_reset_n),
        .clk(clk),
        .clk_en(psg_clock_enable),
        .bdir(psg_bdir),
        .bc1(psg_bc1),
        .din(pia_port_a),
        .sel(1'b1),
        .dout(psg_data_out),
        .sound(psg_sound),
        .A(),
        .B(),
        .C(),
        .sample(psg_sample),
        .IOA_in(8'hff),
        .IOA_out(),
        .IOA_oe(),
        .IOB_in(8'hff),
        .IOB_out(),
        .IOB_oe()
    );

    always @(posedge clk) begin
        if (!psg_reset_n) begin
            audio <= 10'd0;
            audio_toggle <= 1'b0;
        end else if (psg_sample) begin
            audio <= psg_sound;
            audio_toggle <= ~audio_toggle;
        end
    end

endmodule
