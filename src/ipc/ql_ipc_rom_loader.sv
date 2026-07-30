module ql_ipc_rom_loader (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        image_mounted,
    input  wire [63:0] image_size,

    output reg         sd_read_start,
    output reg  [31:0] sd_sector,
    input  wire        sd_busy,
    input  wire        sd_done,
    input  wire        sd_byte_valid,
    input  wire [8:0]  sd_byte_addr,
    input  wire [7:0]  sd_byte,

    output reg         rom_write_enable,
    output reg  [10:0] rom_write_address,
    output reg  [7:0]  rom_write_data,
    output reg         loading,
    output reg         loaded,
    output reg         failed,
    output reg  [7:0]  sector_progress
);

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_REQUEST = 3'd1;
    localparam [2:0] ST_WAIT    = 3'd2;
    localparam [2:0] ST_NEXT    = 3'd3;
    localparam [2:0] ST_DONE    = 3'd4;
    localparam [2:0] ST_FAILED  = 3'd5;
    localparam [1:0] FORMAT_RAW     = 2'd0;
    localparam [1:0] FORMAT_UNKNOWN = 2'd1;
    localparam [1:0] FORMAT_INTEL   = 2'd2;
    localparam [1:0] FORMAT_PLAIN   = 2'd3;

    reg [2:0] state;
    reg [31:0] sector_index;
    reg [31:0] sector_count;
    reg [9:0] sector_byte_count;
    reg mount_pending;
    reg [1:0] input_format;

    reg [11:0] write_count;
    reg parser_error;
    reg eof_seen;
    reg expect_colon;
    reg have_high_nibble;
    reg [3:0] high_nibble;
    reg [8:0] record_byte_index;
    reg [7:0] record_length;
    reg [15:0] record_address;
    reg [7:0] record_type;
    reg [8:0] record_data_count;
    reg [15:0] record_data_word;
    reg [7:0] record_checksum;

    wire [63:0] current_file_offset =
        ({32'd0, sector_index} << 9) + {55'd0, sd_byte_addr};
    wire current_byte_in_file = current_file_offset < image_size;

    function automatic hex_valid;
        input [7:0] character;
        begin
            hex_valid = ((character >= "0") && (character <= "9")) ||
                        ((character >= "A") && (character <= "F")) ||
                        ((character >= "a") && (character <= "f"));
        end
    endfunction

    function automatic [3:0] hex_value;
        input [7:0] character;
        begin
            if ((character >= "A") && (character <= "F"))
                hex_value = character[3:0] + 4'd9;
            else if ((character >= "a") && (character <= "f"))
                hex_value = character[3:0] + 4'd9;
            else
                hex_value = character[3:0];
        end
    endfunction

    wire [7:0] decoded_hex_byte = {high_nibble, hex_value(sd_byte)};
    wire decoded_is_data =
        (record_byte_index >= 9'd4) &&
        (record_byte_index < (9'd4 + {1'b0, record_length}));
    wire decoded_is_checksum =
        record_byte_index == (9'd4 + {1'b0, record_length});

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            sector_index <= 32'd0;
            sector_count <= 32'd0;
            sector_byte_count <= 10'd0;
            mount_pending <= 1'b0;
            input_format <= FORMAT_RAW;
            write_count <= 12'd0;
            parser_error <= 1'b0;
            eof_seen <= 1'b0;
            expect_colon <= 1'b1;
            have_high_nibble <= 1'b0;
            high_nibble <= 4'd0;
            record_byte_index <= 9'd0;
            record_length <= 8'd0;
            record_address <= 16'd0;
            record_type <= 8'd0;
            record_data_count <= 9'd0;
            record_data_word <= 16'd0;
            record_checksum <= 8'd0;
            sd_read_start <= 1'b0;
            sd_sector <= 32'd0;
            rom_write_enable <= 1'b0;
            rom_write_address <= 11'd0;
            rom_write_data <= 8'd0;
            loading <= 1'b0;
            loaded <= 1'b0;
            failed <= 1'b0;
            sector_progress <= 8'd0;
        end else begin
            rom_write_enable <= 1'b0;
            sd_read_start <= 1'b0;

            if (image_mounted) begin
                mount_pending <= 1'b1;
                loaded <= 1'b0;
                failed <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    loading <= 1'b0;
                    if (enable && (mount_pending || image_mounted)) begin
                        mount_pending <= 1'b0;
                        if ((image_size == 64'd2048) ||
                            ((image_size >= 64'd12) &&
                             (image_size <= 64'd65536))) begin
                            input_format <= image_size == 64'd2048 ?
                                            FORMAT_RAW : FORMAT_UNKNOWN;
                            sector_index <= 32'd0;
                            sector_count <=
                                {24'd0, image_size[16:9]} +
                                {{31{1'b0}}, |image_size[8:0]};
                            write_count <= 12'd0;
                            parser_error <= 1'b0;
                            eof_seen <= 1'b0;
                            expect_colon <= 1'b1;
                            have_high_nibble <= 1'b0;
                            record_byte_index <= 9'd0;
                            record_length <= 8'd0;
                            record_address <= 16'd0;
                            record_type <= 8'd0;
                            record_data_count <= 9'd0;
                            record_data_word <= 16'd0;
                            record_checksum <= 8'd0;
                            sector_progress <= 8'd0;
                            loading <= 1'b1;
                            state <= ST_REQUEST;
                        end else if (image_size == 64'd0) begin
                            state <= ST_IDLE;
                        end else begin
                            failed <= 1'b1;
                            state <= ST_FAILED;
                        end
                    end
                end

                ST_REQUEST: begin
                    sd_sector <= sector_index;
                    sd_read_start <= 1'b1;
                    if (sd_busy) begin
                        sector_byte_count <= 10'd0;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (sd_byte_valid) begin
                        if (sector_byte_count != 10'd512)
                            sector_byte_count <= sector_byte_count + 10'd1;

                        if (current_byte_in_file) begin
                            if (input_format == FORMAT_RAW) begin
                                if (write_count < 12'd2048) begin
                                    rom_write_enable <= 1'b1;
                                    rom_write_address <= write_count[10:0];
                                    rom_write_data <= sd_byte;
                                    write_count <= write_count + 12'd1;
                                end else begin
                                    parser_error <= 1'b1;
                                end
                            end else if (input_format == FORMAT_UNKNOWN) begin
                                if ((sd_byte == 8'h0d) ||
                                    (sd_byte == 8'h0a) ||
                                    (sd_byte == 8'h20) ||
                                    (sd_byte == 8'h09)) begin
                                end else if (sd_byte == ":") begin
                                    input_format <= FORMAT_INTEL;
                                    expect_colon <= 1'b0;
                                    have_high_nibble <= 1'b0;
                                    record_byte_index <= 9'd0;
                                    record_data_count <= 9'd0;
                                    record_data_word <= 16'd0;
                                    record_checksum <= 8'd0;
                                end else if (hex_valid(sd_byte)) begin
                                    input_format <= FORMAT_PLAIN;
                                    high_nibble <= hex_value(sd_byte);
                                    have_high_nibble <= 1'b1;
                                end else begin
                                    parser_error <= 1'b1;
                                end
                            end else if (input_format == FORMAT_PLAIN) begin
                                if ((sd_byte == 8'h0d) ||
                                    (sd_byte == 8'h0a) ||
                                    (sd_byte == 8'h20) ||
                                    (sd_byte == 8'h09)) begin
                                    if (have_high_nibble)
                                        parser_error <= 1'b1;
                                end else if (!hex_valid(sd_byte)) begin
                                    parser_error <= 1'b1;
                                end else if (!have_high_nibble) begin
                                    high_nibble <= hex_value(sd_byte);
                                    have_high_nibble <= 1'b1;
                                end else begin
                                    have_high_nibble <= 1'b0;
                                    if (write_count < 12'd2048) begin
                                        rom_write_enable <= 1'b1;
                                        rom_write_address <=
                                            write_count[10:0];
                                        rom_write_data <= decoded_hex_byte;
                                        write_count <= write_count + 12'd1;
                                    end else begin
                                        parser_error <= 1'b1;
                                    end
                                end
                            end else if (eof_seen) begin
                                if ((sd_byte != 8'h0d) && (sd_byte != 8'h0a) &&
                                    (sd_byte != 8'h20) && (sd_byte != 8'h09))
                                    parser_error <= 1'b1;
                            end else if (expect_colon) begin
                                if (sd_byte == ":") begin
                                    expect_colon <= 1'b0;
                                    have_high_nibble <= 1'b0;
                                    record_byte_index <= 9'd0;
                                    record_data_count <= 9'd0;
                                    record_data_word <= 16'd0;
                                    record_checksum <= 8'd0;
                                end else if ((sd_byte != 8'h0d) &&
                                             (sd_byte != 8'h0a) &&
                                             (sd_byte != 8'h20) &&
                                             (sd_byte != 8'h09)) begin
                                    parser_error <= 1'b1;
                                end
                            end else if (!hex_valid(sd_byte)) begin
                                parser_error <= 1'b1;
                            end else if (!have_high_nibble) begin
                                high_nibble <= hex_value(sd_byte);
                                have_high_nibble <= 1'b1;
                            end else begin
                                have_high_nibble <= 1'b0;
                                if (record_byte_index == 9'd0) begin
                                    record_length <= decoded_hex_byte;
                                    record_checksum <= decoded_hex_byte;
                                    record_byte_index <= 9'd1;
                                end else if (record_byte_index == 9'd1) begin
                                    record_address[15:8] <= decoded_hex_byte;
                                    record_checksum <=
                                        record_checksum + decoded_hex_byte;
                                    record_byte_index <= 9'd2;
                                end else if (record_byte_index == 9'd2) begin
                                    record_address[7:0] <= decoded_hex_byte;
                                    record_checksum <=
                                        record_checksum + decoded_hex_byte;
                                    record_byte_index <= 9'd3;
                                end else if (record_byte_index == 9'd3) begin
                                    record_type <= decoded_hex_byte;
                                    record_checksum <=
                                        record_checksum + decoded_hex_byte;
                                    record_byte_index <= 9'd4;
                                end else if (decoded_is_data) begin
                                    record_checksum <=
                                        record_checksum + decoded_hex_byte;
                                    record_byte_index <=
                                        record_byte_index + 9'd1;
                                    if (record_data_count < 9'd2)
                                        record_data_word <=
                                            {record_data_word[7:0],
                                             decoded_hex_byte};
                                    if (record_type == 8'h00) begin
                                        if ((record_address +
                                             record_data_count ==
                                             write_count) &&
                                            (write_count < 12'd2048)) begin
                                            rom_write_enable <= 1'b1;
                                            rom_write_address <=
                                                write_count[10:0];
                                            rom_write_data <= decoded_hex_byte;
                                            write_count <=
                                                write_count + 12'd1;
                                        end else begin
                                            parser_error <= 1'b1;
                                        end
                                    end
                                    record_data_count <=
                                        record_data_count + 9'd1;
                                end else if (decoded_is_checksum) begin
                                    if ((record_checksum +
                                         decoded_hex_byte) != 8'h00)
                                        parser_error <= 1'b1;
                                    if (record_type == 8'h01) begin
                                        if ((record_length != 8'd0) ||
                                            (record_address != 16'd0) ||
                                            (write_count != 12'd2048))
                                            parser_error <= 1'b1;
                                        else
                                            eof_seen <= 1'b1;
                                    end else if ((record_type == 8'h02) ||
                                                 (record_type == 8'h04)) begin
                                        if ((record_length != 8'd2) ||
                                            (record_data_word != 16'd0))
                                            parser_error <= 1'b1;
                                    end else if (record_type != 8'h00) begin
                                        parser_error <= 1'b1;
                                    end
                                    expect_colon <= 1'b1;
                                    record_byte_index <= 9'd0;
                                end else begin
                                    parser_error <= 1'b1;
                                end
                            end
                        end
                    end

                    if (sd_done) begin
                        if ((sector_byte_count != 10'd512) &&
                            !(sd_byte_valid &&
                              sector_byte_count == 10'd511)) begin
                            parser_error <= 1'b1;
                            loading <= 1'b0;
                            failed <= 1'b1;
                            state <= ST_FAILED;
                        end else begin
                            state <= ST_NEXT;
                        end
                    end
                end

                ST_NEXT: begin
                    sector_progress <=
                        sector_progress + ((sector_count <= 32'd4) ? 8'd64 :
                                           (sector_count <= 32'd8) ? 8'd32 :
                                           (sector_count <= 32'd16) ? 8'd16 :
                                           8'd4);
                    if (parser_error) begin
                        failed <= 1'b1;
                        loading <= 1'b0;
                        state <= ST_FAILED;
                    end else if ((sector_index + 32'd1) >= sector_count) begin
                        if ((write_count == 12'd2048) &&
                            ((input_format == FORMAT_RAW) ||
                             ((input_format == FORMAT_PLAIN) &&
                              !have_high_nibble) ||
                             ((input_format == FORMAT_INTEL) &&
                              eof_seen && expect_colon &&
                              !have_high_nibble))) begin
                            loaded <= 1'b1;
                            loading <= 1'b0;
                            sector_progress <= 8'hff;
                            state <= ST_DONE;
                        end else begin
                            failed <= 1'b1;
                            loading <= 1'b0;
                            state <= ST_FAILED;
                        end
                    end else begin
                        sector_index <= sector_index + 32'd1;
                        state <= ST_REQUEST;
                    end
                end

                ST_DONE: begin
                    if (image_mounted)
                        state <= ST_IDLE;
                end

                ST_FAILED: begin
                    if (image_mounted)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
