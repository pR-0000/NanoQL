module ql_sd_rom_loader(
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

    output reg         mem_req,
    output reg         mem_we,
    output reg  [21:0] mem_addr,
    output reg  [1:0]  mem_ds,
    output reg  [15:0] mem_wdata,
    input  wire        mem_ready,
    input  wire        mem_data_valid,
    input  wire [15:0] mem_data,
    input  wire        mem_write_done,

    output reg         loading,
    output reg         loaded,
    output reg         failed,
    output reg  [7:0] sector_progress
);

    localparam [21:0] ROM_BASE = 22'd0;

    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_SD_REQUEST  = 4'd1;
    localparam [3:0] ST_SD_WAIT     = 4'd2;
    localparam [3:0] ST_PREFETCH    = 4'd3;
    localparam [3:0] ST_WRITE_REQ   = 4'd4;
    localparam [3:0] ST_WRITE_WAIT  = 4'd5;
    localparam [3:0] ST_READ_REQ    = 4'd6;
    localparam [3:0] ST_READ_WAIT   = 4'd7;
    localparam [3:0] ST_NEXT_WORD   = 4'd8;
    localparam [3:0] ST_DONE        = 4'd9;
    localparam [3:0] ST_FAILED      = 4'd10;
    localparam [3:0] ST_VALIDATE    = 4'd11;

    reg [3:0] state;
    reg [7:0] sector_index;
    reg [7:0] file_sector_count;
    reg [7:0] word_index;
    reg [7:0] high_byte;
    reg mount_pending;
    reg buffer_we;
    reg [7:0] buffer_waddr;
    reg [15:0] buffer_wdata;
    wire [15:0] buffer_rdata;
    wire padding_sector = sector_index >= file_sector_count;
    wire valid_size = (image_size == 64'd49152) ||
                      (image_size == 64'd65536);

    ql_rom_sector_buffer sector_buffer (
        .clk(clk),
        .write_enable(buffer_we),
        .write_addr(buffer_waddr),
        .write_data(buffer_wdata),
        .read_addr(word_index),
        .read_data(buffer_rdata)
    );

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            sector_index <= 8'd0;
            file_sector_count <= 8'd0;
            word_index <= 8'd0;
            high_byte <= 8'd0;
            mount_pending <= 1'b0;
            buffer_we <= 1'b0;
            buffer_waddr <= 8'd0;
            buffer_wdata <= 16'd0;
            sd_read_start <= 1'b0;
            sd_sector <= 32'd0;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            mem_addr <= ROM_BASE;
            mem_ds <= 2'b00;
            mem_wdata <= 16'hffff;
            loading <= 1'b0;
            loaded <= 1'b0;
            failed <= 1'b0;
            sector_progress <= 8'd0;
        end else begin
            buffer_we <= 1'b0;
            // image_mounted is only one clock wide. The Companion can emit it
            // while SDRAM is still being initialized, so retain the event
            // until the loader is enabled and able to consume it.
            if (image_mounted)
                mount_pending <= 1'b1;

            if (sd_byte_valid) begin
                if (!sd_byte_addr[0]) begin
                    high_byte <= sd_byte;
                end else begin
                    buffer_we <= 1'b1;
                    buffer_waddr <= sd_byte_addr[8:1];
                    buffer_wdata <= {high_byte, sd_byte};
                end
            end

            if (!enable) begin
                state <= ST_IDLE;
                mem_req <= 1'b0;
                sd_read_start <= 1'b0;
                loading <= 1'b0;
                loaded <= 1'b0;
                failed <= 1'b0;
                sector_progress <= 8'd0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        mem_req <= 1'b0;
                        sd_read_start <= 1'b0;
                        loading <= 1'b0;
                        if (mount_pending || image_mounted) begin
                            mount_pending <= 1'b0;
                            loaded <= 1'b0;
                            failed <= 1'b0;
                            // image_size is completed by sd_card on the same
                            // edge as image_mounted, so validate it next cycle.
                            state <= ST_VALIDATE;
                        end
                    end

                    ST_VALIDATE: begin
                        if (valid_size) begin
                            loading <= 1'b1;
                            sector_index <= 8'd0;
                            sector_progress <= 8'd0;
                            file_sector_count <= image_size[16:9];
                            sd_sector <= 32'd0;
                            state <= ST_SD_REQUEST;
                        end else begin
                            failed <= 1'b1;
                            state <= ST_FAILED;
                        end
                    end

                    ST_SD_REQUEST: begin
                        sd_read_start <= 1'b1;
                        state <= ST_SD_WAIT;
                    end

                    ST_SD_WAIT: begin
                        // Keep the request asserted while the Companion is
                        // translating a fragmented file sector. Drop it once
                        // the physical SD transfer has actually started.
                        if (sd_busy)
                            sd_read_start <= 1'b0;
                        if (sd_done) begin
                            sd_read_start <= 1'b0;
                            word_index <= 8'd0;
                            state <= ST_PREFETCH;
                        end
                    end

                    ST_PREFETCH: state <= ST_WRITE_REQ;

                    ST_WRITE_REQ: begin
                        mem_req <= 1'b1;
                        mem_we <= 1'b1;
                        mem_addr <= ROM_BASE +
                                    {sector_index, 8'b00000000} +
                                    {14'd0, word_index};
                        mem_ds <= 2'b00;
                        mem_wdata <= padding_sector ? 16'hffff : buffer_rdata;
                        if (mem_req && mem_ready) begin
                            mem_req <= 1'b0;
                            state <= ST_WRITE_WAIT;
                        end
                    end

                    ST_WRITE_WAIT: begin
                        if (mem_write_done)
                            state <= ST_READ_REQ;
                    end

                    ST_READ_REQ: begin
                        mem_req <= 1'b1;
                        mem_we <= 1'b0;
                        if (mem_req && mem_ready) begin
                            mem_req <= 1'b0;
                            state <= ST_READ_WAIT;
                        end
                    end

                    ST_READ_WAIT: begin
                        if (mem_data_valid) begin
                            if (mem_data != mem_wdata) begin
                                failed <= 1'b1;
                                state <= ST_FAILED;
                            end else begin
                                state <= ST_NEXT_WORD;
                            end
                        end
                    end

                    ST_NEXT_WORD: begin
                        if (word_index != 8'hff) begin
                            word_index <= word_index + 8'd1;
                            state <= padding_sector ? ST_WRITE_REQ : ST_PREFETCH;
                        end else if (sector_index == 8'd127) begin
                            state <= ST_DONE;
                        end else begin
                            sector_index <= sector_index + 8'd1;
                            sector_progress <= sector_index + 8'd1;
                            word_index <= 8'd0;
                            sd_sector <= sd_sector + 32'd1;
                            if ((sector_index + 8'd1) < file_sector_count)
                                state <= ST_SD_REQUEST;
                            else
                                state <= ST_WRITE_REQ;
                        end
                    end

                    ST_DONE: begin
                        sd_read_start <= 1'b0;
                        loading <= 1'b0;
                        loaded <= 1'b1;
                        // image_mounted is a one-cycle event, not a mounted
                        // level. Stay loaded until the Companion emits a new
                        // event after the user selects another ROM.
                        if (image_mounted) begin
                            mount_pending <= 1'b0;
                            loaded <= 1'b0;
                            state <= ST_VALIDATE;
                        end
                    end

                    ST_FAILED: begin
                        mem_req <= 1'b0;
                        sd_read_start <= 1'b0;
                        loading <= 1'b0;
                        loaded <= 1'b0;
                        if (image_mounted) begin
                            mount_pending <= 1'b0;
                            failed <= 1'b0;
                            state <= ST_VALIDATE;
                        end
                    end

                    default: begin
                        mem_req <= 1'b0;
                        sd_read_start <= 1'b0;
                        loading <= 1'b0;
                        loaded <= 1'b0;
                        failed <= 1'b1;
                        state <= ST_FAILED;
                    end
                endcase
            end
        end
    end

endmodule
