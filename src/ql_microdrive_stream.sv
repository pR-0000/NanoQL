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
    input  wire        core_reset,
    input  wire        selected,
    input  wire        status_read_ack,
    input  wire        write_enable,
    input  wire        erase_enable,
    input  wire        tx_write,
    input  wire [7:0]  tx_data,

    input  wire        image_mounted,
    input  wire [63:0] image_size,

    output reg         sd_read_start,
    output reg         sd_write_start,
    output reg  [31:0] sd_sector,
    output wire [7:0]  sd_write_byte,
    input  wire        sd_busy,
    input  wire        sd_done,
    input  wire [2:0]  sd_source,
    input  wire        sd_byte_valid,
    input  wire [8:0]  sd_byte_addr,
    input  wire [7:0]  sd_byte,

    output wire        image_ready,
    output wire        gap,
    output reg         tx_full,
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
    // QDOS emits a variable-length erase preamble before every write. QLAY,
    // however, stores each decoded record at a fixed offset. Capture the
    // logical 612-byte record and merge it back into canonical file sectors.
    reg [7:0] record_ram [0:1023];
    reg [7:0] patch_ram [0:511];
    reg [7:0] incoming_high_byte;
    reg [15:0] stream_word;
    reg [7:0] record_read_byte;
    reg [7:0] patch_read_byte;

    // FPGA configuration values provide a deterministic empty drive before
    // Companion has had a chance to restore a persisted OSD image.
    reg image_valid = 1'b0;
    reg [17:0] image_bytes = 18'd0;
    reg [8:0] image_sector_count = 9'd0;
    reg [1:0] buffer_valid;
    reg [8:0] buffer_sector [0:1];
    reg read_in_flight;
    reg write_in_flight;
    reg [7:0] tx_buffer;

    localparam [3:0] WB_IDLE        = 4'd0;
    localparam [3:0] WB_FILL        = 4'd1;
    localparam [3:0] WB_READ_START  = 4'd2;
    localparam [3:0] WB_READ_WAIT   = 4'd3;
    localparam [3:0] WB_APPLY_SETUP = 4'd4;
    localparam [3:0] WB_APPLY       = 4'd5;
    localparam [3:0] WB_WRITE_START = 4'd6;
    localparam [3:0] WB_WRITE_WAIT  = 4'd7;

    reg [3:0] writeback_state;
    reg previous_write_active;
    reg previous_core_reset;
    reg stream_restart_pending;
    reg [1:0] preamble_ff_count;
    reg [2:0] preamble_zero_count;
    reg capture_active;
    reg [9:0] capture_count;
    reg [7:0] capture_record_index;
    reg [9:0] fill_address;
    reg [17:0] record_file_offset;
    reg [8:0] writeback_first_sector;
    reg [8:0] writeback_first_offset;
    reg [1:0] writeback_sector_count;
    reg [1:0] writeback_sector_index;
    reg [8:0] apply_local_address;
    reg [8:0] apply_write_address;
    reg [9:0] apply_record_address;
    reg [9:0] apply_remaining;
    reg apply_pipeline_valid;

    reg [17:0] byte_position;
    reg [9:0] qlay_record_position;
    reg [7:0] qlay_record_index;
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

    // ZX8302 control bit 2 independently selects the write path. Bit 3 drives
    // the physical erase head; QDOS may change it before or after WRITE, so it
    // must not gate the transmit holding register.
    wire write_active = selected && write_enable;
    wire [17:0] write_byte_position = byte_position >= 18'd2 ?
        byte_position - 18'd2 : image_bytes - 18'd2;
    wire [8:0] sector_read_address = byte_position[9:1];
    wire [9:0] write_record_position = qlay_record_position >= 10'd2 ?
        qlay_record_position - 10'd2 : qlay_record_position + 10'd684;
    wire [7:0] write_record_index = qlay_record_position >= 10'd2 ?
        qlay_record_index :
        (qlay_record_index == 0 ? 8'd254 : qlay_record_index - 8'd1);
    wire [17:0] capture_file_offset =
        capture_record_index * 18'd686 + 18'd40;
    wire [10:0] capture_file_span =
        {2'b00, capture_file_offset[8:0]} + 11'd612;
    wire tx_consume = !core_reset && !stream_restart_pending &&
        stream_started && write_active && tx_full &&
        !read_in_flight &&
        phase_divider == CLOCK_CYCLES_PER_BIT - 1 &&
        (bit_counter == 4'd1 || bit_counter == 4'd9);
    wire incoming_word_write = sd_byte_valid && sd_source == 3'd2 &&
        read_in_flight && sd_byte_addr[0];
    wire sector_ram_write = incoming_word_write &&
        writeback_state == WB_IDLE;
    wire [8:0] sector_ram_write_address =
        {sd_sector[0], sd_byte_addr[8:1]};
    wire [15:0] sector_ram_write_data = {incoming_high_byte, sd_byte};
    wire capture_ram_write = tx_consume && capture_active &&
        capture_count < 10'd612;
    wire fill_ram_write = writeback_state == WB_FILL;
    wire record_ram_write = capture_ram_write || fill_ram_write;
    wire [9:0] record_ram_write_address = fill_ram_write ?
        fill_address : capture_count;
    wire [7:0] record_ram_write_data = fill_ram_write ?
        (fill_address < 10'd610 ?
            (fill_address[0] ? 8'h55 : 8'haa) :
         (fill_address == 10'd610 ? 8'h19 : 8'h3b)) : tx_buffer;
    wire patch_load_write = sd_byte_valid && sd_source == 3'd2 &&
        read_in_flight && writeback_state == WB_READ_WAIT;
    wire patch_apply_write = writeback_state == WB_APPLY &&
        apply_pipeline_valid;
    wire patch_ram_write = patch_load_write || patch_apply_write;
    wire [8:0] patch_ram_write_address = patch_apply_write ?
        apply_write_address : sd_byte_addr;
    wire [7:0] patch_ram_write_data = patch_apply_write ?
        record_read_byte : sd_byte;

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
    assign sd_write_byte = patch_read_byte;
    // NanoQL's synchronous 68000 bridge cannot reliably observe MiSTer's
    // narrow combinational pulse. Offer each byte until QDOS acknowledges it
    // or the following byte arrives. An acknowledged byte drops immediately,
    // preventing duplicate reads without changing the tape cadence.
    wire rx_window = !core_reset && !stream_restart_pending && selected &&
                     current_available && data_valid &&
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
        // One read port and one consolidated write port allow Gowin to infer
        // the two rotating buffers as true block RAM.
        stream_word <= sector_ram[sector_read_address];
        if (sector_ram_write)
            sector_ram[sector_ram_write_address] <= sector_ram_write_data;
        record_read_byte <= record_ram[apply_record_address];
        patch_read_byte <= patch_ram[sd_byte_addr];
        if (record_ram_write)
            record_ram[record_ram_write_address] <= record_ram_write_data;
        if (patch_ram_write)
            patch_ram[patch_ram_write_address] <= patch_ram_write_data;

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
            write_in_flight <= 1'b0;
            writeback_state <= WB_IDLE;
            previous_write_active <= 1'b0;
            previous_core_reset <= core_reset;
            stream_restart_pending <= 1'b0;
            preamble_ff_count <= 2'd0;
            preamble_zero_count <= 3'd0;
            capture_active <= 1'b0;
            capture_count <= 10'd0;
            capture_record_index <= 8'd0;
            fill_address <= 10'd0;
            record_file_offset <= 18'd0;
            writeback_first_sector <= 9'd0;
            writeback_first_offset <= 9'd0;
            writeback_sector_count <= 2'd0;
            writeback_sector_index <= 2'd0;
            apply_local_address <= 9'd0;
            apply_write_address <= 9'd0;
            apply_record_address <= 10'd0;
            apply_remaining <= 10'd0;
            apply_pipeline_valid <= 1'b0;
            sd_read_start <= 1'b0;
            sd_write_start <= 1'b0;
            sd_sector <= 32'd0;
            byte_position <= 18'd0;
            qlay_record_position <= 10'd0;
            qlay_record_index <= 8'd0;
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
            tx_full <= 1'b0;
            tx_buffer <= 8'd0;
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
            write_in_flight <= 1'b0;
            writeback_state <= WB_IDLE;
            previous_write_active <= 1'b0;
            previous_core_reset <= 1'b0;
            stream_restart_pending <= 1'b0;
            preamble_ff_count <= 2'd0;
            preamble_zero_count <= 3'd0;
            capture_active <= 1'b0;
            capture_count <= 10'd0;
            capture_record_index <= 8'd0;
            fill_address <= 10'd0;
            record_file_offset <= 18'd0;
            writeback_first_sector <= 9'd0;
            writeback_first_offset <= 9'd0;
            writeback_sector_count <= 2'd0;
            writeback_sector_index <= 2'd0;
            apply_local_address <= 9'd0;
            apply_write_address <= 9'd0;
            apply_record_address <= 10'd0;
            apply_remaining <= 10'd0;
            apply_pipeline_valid <= 1'b0;
            sd_read_start <= 1'b0;
            sd_write_start <= 1'b0;
            sd_sector <= 32'd0;
            byte_position <= 18'd0;
            qlay_record_position <= 10'd0;
            qlay_record_index <= 8'd0;
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
            tx_full <= 1'b0;
            tx_buffer <= 8'd0;
            data <= 8'd0;
            debug_rx_count <= 16'd0;
            debug_rx_missed_count <= 16'd0;
            debug_rx_xor <= 8'd0;
            debug_rx_last <= 8'd0;
        end else begin
            begin : stream_active
                previous_core_reset <= core_reset;
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

                if (selected && !core_reset && !stream_restart_pending)
                    selection_seen <= 1'b1;

                if (tx_write && selected && !tx_full &&
                    !core_reset && !stream_restart_pending) begin
                    tx_buffer <= tx_data;
                    tx_full <= 1'b1;
                end else if (!write_enable || !selected) begin
                    tx_full <= 1'b0;
                end

                previous_write_active <= write_active;

                // Find the variable QDOS erase preamble (at least two zero
                // bytes followed by FF FF), then capture the decoded record.
                if (write_active && !previous_write_active) begin
                    preamble_ff_count <= 2'd0;
                    preamble_zero_count <= 3'd0;
                    capture_active <= 1'b0;
                    capture_count <= 10'd0;
                end

                if (tx_consume) begin
                    if (capture_active) begin
                        if (capture_count < 10'd612)
                            capture_count <= capture_count + 10'd1;
                    end else if (tx_buffer == 8'h00) begin
                        if (preamble_zero_count != 3'd7)
                            preamble_zero_count <= preamble_zero_count + 3'd1;
                        preamble_ff_count <= 2'd0;
                    end else if (tx_buffer == 8'hff &&
                                 preamble_zero_count >= 3'd2) begin
                        if (preamble_ff_count == 2'd1) begin
                            capture_active <= 1'b1;
                            capture_count <= 10'd0;
                            capture_record_index <= write_record_index;
                            preamble_ff_count <= 2'd0;
                        end else begin
                            preamble_ff_count <= 2'd1;
                        end
                    end else begin
                        preamble_zero_count <= 3'd0;
                        preamble_ff_count <= 2'd0;
                    end
                end

                // A useful QDOS record contains its 526 significant bytes.
                // Any omitted calibration tail is deterministic and is filled
                // before the canonical QLAY file sectors are updated.
                if (previous_write_active && !write_active) begin
                    capture_active <= 1'b0;
                    if (capture_active && capture_count >= 10'd526 &&
                        writeback_state == WB_IDLE) begin
                        record_file_offset <= capture_file_offset;
                        writeback_first_sector <= capture_file_offset[17:9];
                        writeback_first_offset <= capture_file_offset[8:0];
                        writeback_sector_count <=
                            capture_file_span > 11'd1024 ? 2'd3 : 2'd2;
                        writeback_sector_index <= 2'd0;
                        buffer_valid <= 2'b00;
                        stream_started <= 1'b0;
                        rx_ready <= 1'b0;
                        if (capture_count < 10'd612) begin
                            fill_address <= capture_count;
                            writeback_state <= WB_FILL;
                        end else begin
                            writeback_state <= WB_READ_START;
                        end
                    end
                end

                if (sd_byte_valid && sd_source == 3'd2 &&
                    read_in_flight && writeback_state == WB_IDLE) begin
                    if (!sd_byte_addr[0])
                        incoming_high_byte <= sd_byte;
                end

                if (sd_busy && sd_source == 3'd2) begin
                    sd_read_start <= 1'b0;
                    sd_write_start <= 1'b0;
                    if (writeback_state == WB_READ_START)
                        writeback_state <= WB_READ_WAIT;
                    else if (writeback_state == WB_WRITE_START)
                        writeback_state <= WB_WRITE_WAIT;
                end

                if (sd_done && sd_source == 3'd2) begin
                    if (write_in_flight) begin
                        write_in_flight <= 1'b0;
                        sd_write_start <= 1'b0;
                        if (writeback_state == WB_WRITE_WAIT) begin
                            if (writeback_sector_index + 2'd1 >=
                                writeback_sector_count) begin
                                writeback_state <= WB_IDLE;
                                buffer_valid <= 2'b00;
                                stream_started <= 1'b0;
                            end else begin
                                writeback_sector_index <=
                                    writeback_sector_index + 2'd1;
                                writeback_state <= WB_READ_START;
                            end
                        end
                    end else if (read_in_flight) begin
                        read_in_flight <= 1'b0;
                        sd_read_start <= 1'b0;
                        if (writeback_state == WB_READ_WAIT) begin
                            writeback_state <= WB_APPLY_SETUP;
                        end else begin
                            buffer_valid[sd_sector[0]] <= 1'b1;
                            buffer_sector[sd_sector[0]] <= sd_sector[8:0];
                        end
                    end
                end

                case (writeback_state)
                    WB_FILL: begin
                        if (fill_address == 10'd611) begin
                            writeback_state <= WB_READ_START;
                        end else begin
                            fill_address <= fill_address + 10'd1;
                        end
                    end

                    WB_READ_START: begin
                        if (!read_in_flight && !write_in_flight &&
                            !sd_read_start && !sd_write_start) begin
                            sd_sector <= {23'd0, writeback_first_sector} +
                                         writeback_sector_index;
                            sd_read_start <= 1'b1;
                            read_in_flight <= 1'b1;
                        end
                    end

                    WB_APPLY_SETUP: begin
                        apply_pipeline_valid <= 1'b0;
                        if (writeback_sector_index == 2'd0) begin
                            apply_local_address <= writeback_first_offset;
                            apply_record_address <= 10'd0;
                            apply_remaining <= 10'd512 -
                                {1'b0, writeback_first_offset};
                        end else if (writeback_sector_index == 2'd1) begin
                            apply_local_address <= 9'd0;
                            apply_record_address <= 10'd512 -
                                {1'b0, writeback_first_offset};
                            if ({1'b0, writeback_first_offset} + 10'd100 >
                                10'd512)
                                apply_remaining <= 10'd512;
                            else
                                apply_remaining <=
                                    {1'b0, writeback_first_offset} + 10'd100;
                        end else begin
                            apply_local_address <= 9'd0;
                            apply_record_address <= 11'd1024 -
                                {2'b00, writeback_first_offset};
                            apply_remaining <=
                                {1'b0, writeback_first_offset} - 10'd412;
                        end
                        writeback_state <= WB_APPLY;
                    end

                    WB_APPLY: begin
                        if (apply_remaining != 0) begin
                            apply_write_address <= apply_local_address;
                            apply_local_address <= apply_local_address + 9'd1;
                            apply_record_address <=
                                apply_record_address + 10'd1;
                            apply_remaining <= apply_remaining - 10'd1;
                            apply_pipeline_valid <= 1'b1;
                        end else if (apply_pipeline_valid) begin
                            apply_pipeline_valid <= 1'b0;
                            writeback_state <= WB_WRITE_START;
                        end
                    end

                    WB_WRITE_START: begin
                        if (!read_in_flight && !write_in_flight &&
                            !sd_read_start && !sd_write_start) begin
                            sd_sector <= {23'd0, writeback_first_sector} +
                                         writeback_sector_index;
                            sd_write_start <= 1'b1;
                            write_in_flight <= 1'b1;
                        end
                    end

                    default: begin
                    end
                endcase

                // mdv.v continuously advances the cartridge, independently
                // of drive selection. QDOS briefly switches the motor line
                // while scanning; rewinding here would make it see sector 0
                // forever. Wait for both initial buffers, then follow the
                // original continuous replay behaviour.
                if (!core_reset && !stream_restart_pending &&
                    !stream_started && (selection_seen || selected) &&
                    image_valid && current_available && following_available &&
                    writeback_state == WB_IDLE)
                    stream_started <= 1'b1;

                // Keep the current and following file sectors resident.
                if (!core_reset && !stream_restart_pending &&
                    image_valid && !write_active &&
                    writeback_state == WB_IDLE &&
                    !(previous_write_active && capture_active &&
                      capture_count >= 10'd526) &&
                    !read_in_flight && !write_in_flight &&
                    !sd_read_start && !sd_write_start) begin
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

                if (!core_reset && !stream_restart_pending && stream_started &&
                    phase_divider == CLOCK_CYCLES_PER_BIT - 1) begin
                    phase_divider <= {PHASE_DIVIDER_WIDTH{1'b0}};
                    bit_counter <= bit_counter + 4'd1;

                    // The physical ZX8302 consumes one transmit byte on each
                    // 40 us half-word slot. Status bit 1 remains high while
                    // the one-byte holding register is occupied.
                    if (tx_consume) begin
                        if (bit_counter == 4'd1) begin
                            microdrive_word[15:8] <= tx_buffer;
                        end else begin
                            microdrive_word[7:0] <= tx_buffer;
                        end
                        tx_full <= 1'b0;
                    end

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
                                    qlay_record_position <= 10'd0;
                                    qlay_record_index <= 8'd0;
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
                                    if (qlay_record_position == 10'd684) begin
                                        qlay_record_position <= 10'd0;
                                        qlay_record_index <=
                                            qlay_record_index == 8'd254 ?
                                            8'd0 : qlay_record_index + 8'd1;
                                    end else begin
                                        qlay_record_position <=
                                            qlay_record_position + 10'd2;
                                    end

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
                end else if (!core_reset && !stream_restart_pending &&
                             stream_started) begin
                    phase_divider <= phase_divider + 1'b1;
                end

                // A QL reset restarts the logical cartridge scan at its
                // beginning. If RESET follows SAVE immediately, first let
                // the normalized record reach the microSD; aborting that
                // writeback would leave a valid image with stale sectors.
                if (core_reset && !previous_core_reset) begin
                    stream_restart_pending <= 1'b1;
                    rx_ready <= 1'b0;
                    previous_rx_window <= 1'b0;
                end

                if (stream_restart_pending && !core_reset &&
                    writeback_state == WB_IDLE && !write_active &&
                    !previous_write_active && !read_in_flight &&
                    !write_in_flight && !sd_read_start && !sd_write_start) begin
                    byte_position <= 18'd0;
                    qlay_record_position <= 10'd0;
                    qlay_record_index <= 8'd0;
                    buffer_valid <= 2'b00;
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
                    tx_full <= 1'b0;
                    preamble_ff_count <= 2'd0;
                    preamble_zero_count <= 3'd0;
                    capture_active <= 1'b0;
                    capture_count <= 10'd0;
                    stream_restart_pending <= 1'b0;
                end
            end
        end
    end

endmodule
