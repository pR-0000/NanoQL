module ql_sdram_memory #(
    parameter [18:0] INIT_LAST_WORD_INDEX = 19'h6ffff
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        fast_cpu,

    input  wire [18:0] client_addr,
    input  wire        client_rd,
    output wire        client_ready,
    output reg         client_data_valid,
    output reg  [15:0] client_data,

    input  wire        system_req,
    input  wire        system_we,
    input  wire [21:0] system_addr,
    input  wire [1:0]  system_ds,
    input  wire [15:0] system_wdata,
    output wire        system_ready,
    output reg         system_data_valid,
    output reg  [15:0] system_data,
    output reg         system_write_done,

    output wire        sdram_clk,
    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_cas_n,
    output wire        sdram_ras_n,
    output wire        sdram_wen_n,
    inout  wire [31:0] sdram_dq,
    output wire [10:0] sdram_addr,
    output wire [1:0]  sdram_ba,
    output wire [3:0]  sdram_dqm,

    output reg         init_done,
    output reg         init_fail
);

    localparam [18:0] SCREEN_BASE_0 = 19'h10000;

    localparam [3:0] ST_WAIT_INIT     = 4'd0;
    localparam [3:0] ST_WRITE_START   = 4'd1;
    localparam [3:0] ST_WRITE_WAIT    = 4'd2;
    localparam [3:0] ST_VERIFY_START  = 4'd3;
    localparam [3:0] ST_VERIFY_WAIT   = 4'd4;
    localparam [3:0] ST_CLIENT_IDLE   = 4'd5;
    localparam [3:0] ST_CLIENT_WAIT   = 4'd6;
    localparam [3:0] ST_REFRESH_START = 4'd7;
    localparam [3:0] ST_REFRESH_WAIT  = 4'd8;

    localparam [1:0] RESUME_WRITE  = 2'd0;
    localparam [1:0] RESUME_VERIFY = 2'd1;
    localparam [1:0] RESUME_CLIENT = 2'd2;
    // The SDRAM core captures read data five clocks after a request. Two
    // further clocks provide a safe registered-data margin without retaining
    // the former four-clock idle tail on every transaction.
    localparam [3:0] TRANSACTION_WAIT = 4'd6;
    localparam [3:0] FAST_CPU_WAIT = 4'd8;

    reg [3:0] state;
    reg [1:0] resume_state;
    reg [3:0] wait_count;
    reg [18:0] init_index;
    reg [7:0] refresh_counter;
    reg refresh_pending;

    reg [21:0] ram_addr;
    reg [15:0] ram_din;
    wire [15:0] ram_dout;
    reg ram_cs;
    reg ram_we;
    reg [1:0] ram_ds;
    reg ram_refresh;
    reg transaction_system;
    reg prefer_video;
    reg [1:0] fast_video_streak;
    wire ram_ready;

    wire [15:0] init_pattern;
    ql_test_pattern pattern_generator (
        .mode8(init_index[14]),
        .word_addr(init_index[13:0]),
        .data(init_pattern)
    );

    // Initialize the complete 896 KiB QL RAM range before releasing the CPU.
    // The first 64 KiB retain the diagnostic screen patterns used at startup;
    // every remaining word is cleared for deterministic expansion RAM.
    wire [18:0] init_word_addr = SCREEN_BASE_0 + init_index;
    wire [15:0] init_data = (init_index < 19'h08000) ?
                            init_pattern : 16'h0000;

    // Alternate at transaction granularity when CPU and video are both
    // waiting. A complete 64-word video burst must not block ROM instruction
    // fetches, but absolute CPU priority can starve the HDMI line buffer at
    // 16 MHz. RAM contention visible to the CPU remains modeled by ql_timing.
    wire client_idle = init_done && !init_fail &&
                       (state == ST_CLIENT_IDLE) && !refresh_pending;
    wire grant_video = client_idle && client_rd &&
                       (!system_req || (fast_cpu ?
                        (fast_video_streak < 2'd2) : prefer_video));
    wire grant_system = client_idle && system_req && !grant_video;
    assign client_ready = init_done && !init_fail &&
                          grant_video;
    assign system_ready = grant_system;

    wire [12:0] controller_addr;
    assign sdram_addr = controller_addr[10:0];

    sdram controller (
        .sd_clk(sdram_clk),
        .sd_cke(sdram_cke),
        .sd_data(sdram_dq),
        .sd_addr(controller_addr),
        .sd_dqm(sdram_dqm),
        .sd_ba(sdram_ba),
        .sd_cs(sdram_cs_n),
        .sd_we(sdram_wen_n),
        .sd_ras(sdram_ras_n),
        .sd_cas(sdram_cas_n),
        .clk(clk),
        .reset_n(!reset),
        .ready(ram_ready),
        .refresh(ram_refresh),
        .din(ram_din),
        .dout(ram_dout),
        .addr(ram_addr),
        .ds(ram_ds),
        .cs(ram_cs),
        .we(ram_we)
    );

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_WAIT_INIT;
            resume_state <= RESUME_WRITE;
            wait_count <= 4'd0;
            init_index <= 19'd0;
            refresh_counter <= 8'd0;
            refresh_pending <= 1'b0;
            ram_addr <= 22'd0;
            ram_din <= 16'd0;
            ram_cs <= 1'b0;
            ram_we <= 1'b0;
            ram_ds <= 2'b00;
            ram_refresh <= 1'b0;
            transaction_system <= 1'b0;
            prefer_video <= 1'b1;
            fast_video_streak <= 2'd0;
            client_data_valid <= 1'b0;
            client_data <= 16'd0;
            system_data_valid <= 1'b0;
            system_data <= 16'd0;
            system_write_done <= 1'b0;
            init_done <= 1'b0;
            init_fail <= 1'b0;
        end else begin
            client_data_valid <= 1'b0;
            system_data_valid <= 1'b0;
            system_write_done <= 1'b0;

            if (ram_ready) begin
                if (refresh_counter == 8'hff) begin
                    refresh_counter <= 8'd0;
                    refresh_pending <= 1'b1;
                end else begin
                    refresh_counter <= refresh_counter + 8'd1;
                end
            end

            case (state)
                ST_WAIT_INIT: begin
                    ram_cs <= 1'b0;
                    if (ram_ready)
                        state <= ST_WRITE_START;
                end

                ST_WRITE_START: begin
                    if (refresh_pending) begin
                        resume_state <= RESUME_WRITE;
                        state <= ST_REFRESH_START;
                    end else begin
                        ram_addr <= {3'd0, init_word_addr};
                        ram_din <= init_data;
                        ram_we <= 1'b1;
                        ram_ds <= 2'b00;
                        ram_refresh <= 1'b0;
                        ram_cs <= 1'b1;
                        wait_count <= 4'd0;
                        state <= ST_WRITE_WAIT;
                    end
                end

                ST_WRITE_WAIT: begin
                    if (wait_count == TRANSACTION_WAIT) begin
                        ram_cs <= 1'b0;
                        if (init_index == INIT_LAST_WORD_INDEX) begin
                            init_index <= 19'd0;
                            state <= ST_VERIFY_START;
                        end else begin
                            init_index <= init_index + 19'd1;
                            state <= ST_WRITE_START;
                        end
                    end else begin
                        wait_count <= wait_count + 4'd1;
                    end
                end

                ST_VERIFY_START: begin
                    if (refresh_pending) begin
                        resume_state <= RESUME_VERIFY;
                        state <= ST_REFRESH_START;
                    end else begin
                        ram_addr <= {3'd0, init_word_addr};
                        ram_we <= 1'b0;
                        ram_ds <= 2'b00;
                        ram_refresh <= 1'b0;
                        ram_cs <= 1'b1;
                        wait_count <= 4'd0;
                        state <= ST_VERIFY_WAIT;
                    end
                end

                ST_VERIFY_WAIT: begin
                    if (wait_count == TRANSACTION_WAIT) begin
                        ram_cs <= 1'b0;
                        if (ram_dout != init_data)
                            init_fail <= 1'b1;

                        if (init_index == INIT_LAST_WORD_INDEX) begin
                            init_done <= 1'b1;
                            state <= ST_CLIENT_IDLE;
                        end else begin
                            init_index <= init_index + 19'd1;
                            state <= ST_VERIFY_START;
                        end
                    end else begin
                        wait_count <= wait_count + 4'd1;
                    end
                end

                ST_CLIENT_IDLE: begin
                    ram_cs <= 1'b0;
                    if (refresh_pending) begin
                        resume_state <= RESUME_CLIENT;
                        state <= ST_REFRESH_START;
                    end else if (grant_system) begin
                        ram_addr <= system_addr;
                        ram_din <= system_wdata;
                        ram_we <= system_we;
                        ram_ds <= system_we ? system_ds : 2'b00;
                        ram_refresh <= 1'b0;
                        ram_cs <= 1'b1;
                        transaction_system <= 1'b1;
                        prefer_video <= 1'b1;
                        fast_video_streak <= 2'd0;
                        wait_count <= 4'd0;
                        state <= ST_CLIENT_WAIT;
                    end else if (grant_video) begin
                        ram_addr <= {3'd0, client_addr};
                        ram_we <= 1'b0;
                        ram_ds <= 2'b00;
                        ram_refresh <= 1'b0;
                        ram_cs <= 1'b1;
                        transaction_system <= 1'b0;
                        prefer_video <= 1'b0;
                        if (fast_cpu && (fast_video_streak < 2'd2))
                            fast_video_streak <= fast_video_streak + 2'd1;
                        wait_count <= 4'd0;
                        state <= ST_CLIENT_WAIT;
                    end
                end

                ST_CLIENT_WAIT: begin
                    if (wait_count == ((transaction_system && fast_cpu) ?
                                      FAST_CPU_WAIT : TRANSACTION_WAIT)) begin
                        ram_cs <= 1'b0;
                        if (transaction_system) begin
                            if (!ram_we) begin
                                system_data <= ram_dout;
                                system_data_valid <= 1'b1;
                            end else
                                system_write_done <= 1'b1;
                            state <= ST_CLIENT_IDLE;
                        end else begin
                            client_data <= ram_dout;
                            client_data_valid <= 1'b1;
                            state <= ST_CLIENT_IDLE;
                        end
                    end else begin
                        wait_count <= wait_count + 4'd1;
                    end
                end

                ST_REFRESH_START: begin
                    ram_we <= 1'b0;
                    ram_refresh <= 1'b1;
                    ram_cs <= 1'b1;
                    wait_count <= 4'd0;
                    state <= ST_REFRESH_WAIT;
                end

                default: begin
                    if (wait_count == TRANSACTION_WAIT) begin
                        ram_cs <= 1'b0;
                        refresh_pending <= 1'b0;
                        if (resume_state == RESUME_WRITE)
                            state <= ST_WRITE_START;
                        else if (resume_state == RESUME_VERIFY)
                            state <= ST_VERIFY_START;
                        else
                            state <= ST_CLIENT_IDLE;
                    end else begin
                        wait_count <= wait_count + 4'd1;
                    end
                end
            endcase
        end
    end

endmodule
