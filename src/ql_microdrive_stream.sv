// SPDX-License-Identifier: GPL-3.0-or-later
// QLAY Microdrive image streamer for NanoQL.
//
// The complete 174,930-byte cartridge does not fit in Tang Nano 20K BSRAM.
// Two 512-byte buffers are therefore filled through FPGA Companion image
// channel 2 while the ZX8302-facing serialized stream runs at 200 kbit/s.
module ql_microdrive_stream #(
    // QLAY stores two bytes per 16-bit tape word. The MiSTer model serializes
    // those words at 200 kbit/s, producing one word every 80 us and 2.8 ms
    // for a 35-word gap. Derive this cadence from the fixed 31.8 MHz clock so
    // CPU speed changes cannot alter the tape.
    parameter integer CLOCK_CYCLES_PER_BIT = 159
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        selected,
    input  wire        status_read_ack,

    input  wire        image_mounted,
    input  wire [63:0] image_size,

    output reg         sd_read_start,
    output reg  [31:0] sd_sector,
    input  wire        sd_busy,
    input  wire        sd_done,
    input  wire [2:0]  sd_source,
    input  wire        sd_byte_valid,
    input  wire [8:0]  sd_byte_addr,
    input  wire [7:0]  sd_byte,

    output wire        image_ready,
    output wire        gap,
    output wire        tx_empty,
    output reg         rx_ready,
    output reg  [7:0]  data,

    output wire [7:0]  debug_flags,
    output wire [17:0] debug_byte_position,
    output wire [8:0]  debug_current_sector,
    output wire [1:0]  debug_buffer_valid,
    output wire [8:0]  debug_buffer_sector_0,
    output wire [8:0]  debug_buffer_sector_1,
    output wire [3:0]  debug_bit_counter,
    output wire        debug_header_phase,
    output wire        debug_data_phase,
    output reg  [15:0] debug_rx_count,
    output reg  [15:0] debug_rx_missed_count,
    output reg  [7:0]  debug_rx_xor,
    output reg  [7:0]  debug_rx_last
);

    localparam integer QLAY_IMAGE_SIZE = 174930;
    localparam integer QLAY_SECTORS =
        (QLAY_IMAGE_SIZE + 511) / 512;
    localparam integer PHASE_DIVIDER_WIDTH =
        $clog2(CLOCK_CYCLES_PER_BIT);

    // Each physical sector is even-sized, so byte pairs can be stored as
    // words. The high address bit selects one of the two rotating buffers.
    reg [15:0] sector_ram [0:511];
    reg [7:0] incoming_high_byte;
    reg [15:0] stream_word;

    // FPGA configuration values provide a deterministic empty drive before
    // Companion has had a chance to restore a persisted OSD image.
    reg image_valid = 1'b0;
    reg [17:0] image_bytes = 18'd0;
    reg [8:0] image_sector_count = 9'd0;
    reg [1:0] buffer_valid;
    reg [8:0] buffer_sector [0:1];
    reg read_in_flight;

    reg [17:0] byte_position;
    reg [PHASE_DIVIDER_WIDTH-1:0] phase_divider;
    reg [3:0] bit_counter;
    reg [9:0] gap_word_count;
    reg gap_state;
    reg gap_active;
    reg gap_reg;
    reg data_valid;
    reg [15:0] microdrive_word;
    reg stream_started;
    reg selection_seen;
    reg previous_rx_window;

    wire [8:0] current_sector = byte_position[17:9];
    wire current_buffer = current_sector[0];
    wire current_available = image_valid &&
        buffer_valid[current_buffer] &&
        buffer_sector[current_buffer] == current_sector;
    wire [9:0] following_sector = {1'b0, current_sector} + 10'd1;
    wire following_available = following_sector < image_sector_count &&
        buffer_valid[following_sector[0]] &&
        buffer_sector[following_sector[0]] == following_sector[8:0];

    assign image_ready = image_valid && buffer_valid[0] &&
                         buffer_sector[0] == 9'd0;
    assign gap = !selected || !current_available || gap_reg;
    assign tx_empty = 1'b0;
    // NanoQL's synchronous 68000 bridge cannot reliably observe MiSTer's
    // narrow combinational pulse. Offer each byte until QDOS acknowledges it
    // or the following byte arrives. An acknowledged byte drops immediately,
    // preventing duplicate reads without changing the tape cadence.
    wire rx_window = selected && current_available && data_valid &&
                     bit_counter[2:0] == 3'd2;
    wire [7:0] stream_data = bit_counter[3] ? microdrive_word[7:0] :
                                             microdrive_word[15:8];
    assign debug_flags = {
        read_in_flight, rx_ready, gap, current_available,
        stream_started, selected, image_ready, image_valid
    };
    assign debug_byte_position = byte_position;
    assign debug_current_sector = current_sector;
    assign debug_buffer_valid = buffer_valid;
    assign debug_buffer_sector_0 = buffer_sector[0];
    assign debug_buffer_sector_1 = buffer_sector[1];
    assign debug_bit_counter = bit_counter;
    // Low gap_state covers the header transfer and the following gap. This
    // leaves enough time to include a delayed final 68000 data-register read.
    assign debug_header_phase = !gap_state;
    assign debug_data_phase = gap_state;

    always @(posedge clk) begin
        // Synchronous read allows Gowin to infer block RAM for the buffers.
        stream_word <= sector_ram[byte_position[9:1]];

        // Companion can restore a persisted image while video reset is still
        // asserted. Give the mount event priority and retain it through the
        // remaining reset cycles.
        if (image_mounted) begin
            image_valid <= image_size == QLAY_IMAGE_SIZE;
            image_bytes <= image_size == QLAY_IMAGE_SIZE ?
                           QLAY_IMAGE_SIZE : 18'd0;
            image_sector_count <= image_size == QLAY_IMAGE_SIZE ?
                                  QLAY_SECTORS : 9'd0;
            buffer_valid <= 2'b00;
            read_in_flight <= 1'b0;
            sd_read_start <= 1'b0;
            sd_sector <= 32'd0;
            byte_position <= 18'd0;
            phase_divider <= {PHASE_DIVIDER_WIDTH{1'b0}};
            bit_counter <= 4'd0;
            gap_word_count <= 10'd0;
            gap_state <= 1'b1;
            gap_active <= 1'b1;
            gap_reg <= 1'b1;
            data_valid <= 1'b0;
            stream_started <= 1'b0;
            selection_seen <= 1'b0;
            previous_rx_window <= 1'b0;
            rx_ready <= 1'b0;
            data <= 8'd0;
            debug_rx_count <= 16'd0;
            debug_rx_missed_count <= 16'd0;
            debug_rx_xor <= 8'd0;
            debug_rx_last <= 8'd0;
        end else if (reset) begin
            buffer_valid <= 2'b00;
            buffer_sector[0] <= 9'd0;
            buffer_sector[1] <= 9'd0;
            incoming_high_byte <= 8'd0;
            read_in_flight <= 1'b0;
            sd_read_start <= 1'b0;
            sd_sector <= 32'd0;
            byte_position <= 18'd0;
            phase_divider <= {PHASE_DIVIDER_WIDTH{1'b0}};
            bit_counter <= 4'd0;
            gap_word_count <= 10'd0;
            gap_state <= 1'b1;
            gap_active <= 1'b1;
            gap_reg <= 1'b1;
            data_valid <= 1'b0;
            microdrive_word <= 16'd0;
            stream_started <= 1'b0;
            selection_seen <= 1'b0;
            previous_rx_window <= 1'b0;
            rx_ready <= 1'b0;
            data <= 8'd0;
            debug_rx_count <= 16'd0;
            debug_rx_missed_count <= 16'd0;
            debug_rx_xor <= 8'd0;
            debug_rx_last <= 8'd0;
        end else begin
            begin : stream_active
                previous_rx_window <= rx_window;
                if (rx_window && !previous_rx_window) begin
                    if (rx_ready)
                        debug_rx_missed_count <=
                            debug_rx_missed_count + 16'd1;
                    debug_rx_count <= debug_rx_count + 16'd1;
                    debug_rx_xor <= debug_rx_xor ^ stream_data;
                    debug_rx_last <= stream_data;
                    data <= stream_data;
                    rx_ready <= 1'b1;
                end else if (status_read_ack && rx_ready) begin
                    rx_ready <= 1'b0;
                end

                if (!selected || !current_available || !data_valid)
                    rx_ready <= 1'b0;

                if (selected)
                    selection_seen <= 1'b1;

                if (sd_byte_valid && sd_source == 3'd2) begin
                    if (!sd_byte_addr[0])
                        incoming_high_byte <= sd_byte;
                    else
                        sector_ram[{sd_sector[0], sd_byte_addr[8:1]}] <=
                            {incoming_high_byte, sd_byte};
                end

                if (sd_busy && sd_source == 3'd2)
                    sd_read_start <= 1'b0;

                if (sd_done && sd_source == 3'd2) begin
                    buffer_valid[sd_sector[0]] <= 1'b1;
                    buffer_sector[sd_sector[0]] <= sd_sector[8:0];
                    read_in_flight <= 1'b0;
                    sd_read_start <= 1'b0;
                end

                // mdv.v continuously advances the cartridge, independently
                // of drive selection. QDOS briefly switches the motor line
                // while scanning; rewinding here would make it see sector 0
                // forever. Wait for both initial buffers, then follow the
                // original continuous replay behaviour.
                if (!stream_started && (selection_seen || selected) &&
                    image_valid &&
                    buffer_valid[0] && buffer_sector[0] == 9'd0 &&
                    buffer_valid[1] && buffer_sector[1] == 9'd1)
                    stream_started <= 1'b1;

                // Keep the current and following file sectors resident.
                if (image_valid && !read_in_flight && !sd_read_start) begin
                    if (!current_available) begin
                        sd_sector <= {23'd0, current_sector};
                        sd_read_start <= 1'b1;
                        read_in_flight <= 1'b1;
                    end else if (following_sector < image_sector_count &&
                                 !following_available) begin
                        sd_sector <= {22'd0, following_sector};
                        sd_read_start <= 1'b1;
                        read_in_flight <= 1'b1;
                    end
                end

                if (stream_started &&
                    phase_divider == CLOCK_CYCLES_PER_BIT - 1) begin
                    phase_divider <= {PHASE_DIVIDER_WIDTH{1'b0}};
                    bit_counter <= bit_counter + 4'd1;

                    if (bit_counter == 4'd15) begin
                        if (!current_available) begin
                            gap_word_count <= 10'd0;
                            gap_state <= 1'b1;
                            gap_active <= 1'b1;
                            gap_reg <= 1'b1;
                            data_valid <= 1'b0;
                        end else begin
                            microdrive_word <= stream_word;
                            // Match the original QL/MiSTer data-valid window:
                            // hide the zero/FF preambles while still replaying
                            // every physical word at the cartridge data rate.
                            data_valid <= !gap_active &&
                                (gap_word_count > 10'd5) &&
                                !(gap_state &&
                                  gap_word_count > 10'd7 &&
                                  gap_word_count < 10'd12);

                            if (gap_active) begin
                                if (gap_word_count == 10'd34) begin
                                    gap_word_count <= 10'd0;
                                    gap_active <= 1'b0;
                                    gap_state <= !gap_state;
                                    gap_reg <= 1'b0;
                                end else begin
                                    gap_word_count <= gap_word_count + 10'd1;
                                end
                            end else begin
                                if (byte_position + 18'd2 >= image_bytes) begin
                                    byte_position <= 18'd0;
                                    buffer_valid <= 2'b00;
                                    stream_started <= 1'b0;
                                    gap_word_count <= 10'd0;
                                    gap_state <= 1'b1;
                                    gap_active <= 1'b1;
                                    gap_reg <= 1'b1;
                                end else begin
                                    if (byte_position[8:0] == 9'd510)
                                        buffer_valid[current_buffer] <= 1'b0;
                                    byte_position <= byte_position + 18'd2;

                                    if ((!gap_state &&
                                         gap_word_count == 10'd13) ||
                                        (gap_state &&
                                         gap_word_count == 10'd328)) begin
                                        gap_word_count <= 10'd0;
                                        gap_active <= 1'b1;
                                        gap_reg <= 1'b1;
                                    end else begin
                                        gap_word_count <= gap_word_count + 10'd1;
                                    end
                                end
                            end
                        end
                    end
                end else if (stream_started) begin
                    phase_divider <= phase_divider + 1'b1;
                end
            end
        end
    end

endmodule
