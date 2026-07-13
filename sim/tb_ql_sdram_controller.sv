`timescale 1ns/1ps

module tb_ql_sdram_controller;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    reg [1:0] phase_div = 2'd0;
    wire ce_bus_p = phase_div == 2'd0;
    always @(posedge clk)
        phase_div <= phase_div + 2'd1;

    reg [23:0] cpu_addr = 24'd0;
    reg [15:0] cpu_data_out = 16'd0;
    wire [15:0] cpu_data_in;
    reg cpu_as_n = 1'b1;
    reg cpu_rw = 1'b1;
    reg cpu_uds_n = 1'b1;
    reg cpu_lds_n = 1'b1;
    wire cpu_dtack_n;

    wire system_req;
    wire system_we;
    wire [21:0] system_addr;
    wire [1:0] system_ds;
    wire [15:0] system_wdata;
    wire system_ready;
    wire system_data_valid;
    wire [15:0] system_data;
    wire system_write_done;

    reg [18:0] client_addr = 19'h10000;
    reg client_rd = 1'b0;
    wire client_ready;
    wire client_data_valid;
    wire [15:0] client_data;
    reg [6:0] video_issue_count = 7'd0;
    reg [7:0] video_gap = 8'd0;

    wire sdram_clk;
    wire sdram_cke;
    wire sdram_cs_n;
    wire sdram_cas_n;
    wire sdram_ras_n;
    wire sdram_wen_n;
    wire [31:0] sdram_dq;
    wire [10:0] sdram_addr;
    wire [1:0] sdram_ba;
    wire [3:0] sdram_dqm;
    wire init_done;
    wire init_fail;

    ql_cpu_bus_bridge bridge (
        .clk(clk), .reset(reset),
        .cpu_addr(cpu_addr), .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in), .cpu_as_n(cpu_as_n), .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n), .cpu_lds_n(cpu_lds_n),
        .cpu_iack(1'b0),
        .cpu_dtack_n(cpu_dtack_n), .timing_delay(1'b0),
        .ce_bus_p(ce_bus_p), .system_req(system_req),
        .system_we(system_we), .system_addr(system_addr),
        .system_ds(system_ds), .system_wdata(system_wdata),
        .system_ready(system_ready), .system_data_valid(system_data_valid),
        .system_data(system_data), .system_write_done(system_write_done)
    );

    ql_sdram_memory memory (
        .clk(clk), .reset(reset),
        .client_addr(client_addr), .client_rd(client_rd),
        .client_ready(client_ready),
        .client_data_valid(client_data_valid), .client_data(client_data),
        .system_req(system_req), .system_we(system_we),
        .system_addr(system_addr), .system_ds(system_ds),
        .system_wdata(system_wdata), .system_ready(system_ready),
        .system_data_valid(system_data_valid), .system_data(system_data),
        .system_write_done(system_write_done),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n), .sdram_cas_n(sdram_cas_n),
        .sdram_ras_n(sdram_ras_n), .sdram_wen_n(sdram_wen_n),
        .sdram_dq(sdram_dq), .sdram_addr(sdram_addr),
        .sdram_ba(sdram_ba), .sdram_dqm(sdram_dqm),
        .init_done(init_done), .init_fail(init_fail)
    );

    // Reproduce the scanout client's bursts of 64 consecutive words. CPU
    // accesses must wait, then resume without losing either byte lane.
    always @(posedge clk) begin
        if (reset || !init_done) begin
            client_addr <= 19'h10000;
            client_rd <= 1'b0;
            video_issue_count <= 7'd0;
            video_gap <= 8'd0;
        end else if (client_rd) begin
            if (client_ready) begin
                client_addr <= client_addr + 19'd1;
                video_issue_count <= video_issue_count + 7'd1;
                if (video_issue_count == 7'd63) begin
                    client_rd <= 1'b0;
                    video_issue_count <= 7'd0;
                    video_gap <= 8'd96;
                end
            end
        end else if (video_gap != 8'd0) begin
            video_gap <= video_gap - 8'd1;
        end else begin
            client_rd <= 1'b1;
        end
    end

    sdram_chip_model chip (
        .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n),
        .ras_n(sdram_ras_n), .cas_n(sdram_cas_n), .we_n(sdram_wen_n),
        .addr(sdram_addr), .ba(sdram_ba), .dqm(sdram_dqm), .dq(sdram_dq)
    );

    task automatic cpu_write;
        input [23:0] address;
        input [15:0] data;
        input uds_n;
        input lds_n;
        integer timeout;
        begin
            @(posedge clk);
            cpu_addr <= address;
            cpu_data_out <= data;
            cpu_rw <= 1'b0;
            cpu_uds_n <= uds_n;
            cpu_lds_n <= lds_n;
            cpu_as_n <= 1'b0;
            timeout = 0;
            while (cpu_dtack_n && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 2000)
                $fatal(1, "write timeout at %h", address);
            @(posedge clk);
            cpu_as_n <= 1'b1;
            cpu_rw <= 1'b1;
            cpu_uds_n <= 1'b1;
            cpu_lds_n <= 1'b1;
            wait (cpu_dtack_n);
        end
    endtask

    task automatic cpu_read_word;
        input [23:0] address;
        input [15:0] expected;
        integer timeout;
        begin
            @(posedge clk);
            cpu_addr <= address;
            cpu_rw <= 1'b1;
            cpu_uds_n <= 1'b0;
            cpu_lds_n <= 1'b0;
            cpu_as_n <= 1'b0;
            timeout = 0;
            while (cpu_dtack_n && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 2000)
                $fatal(1, "read timeout at %h", address);
            if (cpu_data_in !== expected)
                $fatal(1, "read %h at %h, expected %h",
                       cpu_data_in, address, expected);
            @(posedge clk);
            cpu_as_n <= 1'b1;
            cpu_uds_n <= 1'b1;
            cpu_lds_n <= 1'b1;
            wait (cpu_dtack_n);
        end
    endtask

    initial begin
        integer i;
        reg [23:0] stress_addr;
        reg [15:0] expected;

        repeat (8) @(posedge clk);
        reset <= 1'b0;
        wait (init_done || init_fail);
        if (init_fail)
            $fatal(1, "physical SDRAM initialization failed");
        if (chip.precharge_count < 1 || chip.refresh_count < 2 ||
            chip.mode_count < 1)
            $fatal(1, "incomplete SDRAM power-up sequence: P=%0d R=%0d M=%0d",
                   chip.precharge_count, chip.refresh_count, chip.mode_count);

        cpu_write(24'h020120, 16'h1234, 1'b0, 1'b0);
        cpu_read_word(24'h020120, 16'h1234);
        cpu_write(24'h020120, 16'hab00, 1'b0, 1'b1);
        cpu_read_word(24'h020120, 16'hab34);
        cpu_write(24'h020120, 16'h00cd, 1'b1, 1'b0);
        cpu_read_word(24'h020120, 16'habcd);

        // Exercise both 16-bit halves of one physical 32-bit SDRAM word.
        cpu_write(24'h020122, 16'h55aa, 1'b0, 1'b0);
        cpu_read_word(24'h020120, 16'habcd);
        cpu_read_word(24'h020122, 16'h55aa);

        for (i = 0; i < 64; i = i + 1) begin
            stress_addr = 24'h020200 + (i * 2);
            cpu_write(stress_addr, 16'h5aa5 ^ i, 1'b0, 1'b0);
            cpu_write(stress_addr, {i[7:0], 8'h00}, 1'b0, 1'b1);
            cpu_write(stress_addr, {8'h00, ~i[7:0]}, 1'b1, 1'b0);
            expected = {i[7:0], ~i[7:0]};
            cpu_read_word(stress_addr, expected);
        end

        $display("PASS: physical SDRAM byte writes survive video contention");
        $finish;
    end
endmodule

module sdram_chip_model (
    input wire clk,
    input wire cke,
    input wire cs_n,
    input wire ras_n,
    input wire cas_n,
    input wire we_n,
    input wire [10:0] addr,
    input wire [1:0] ba,
    input wire [3:0] dqm,
    inout wire [31:0] dq
);
    reg [10:0] active_row [0:3];
    reg [31:0] words [0:2097151];
    reg [31:0] read_data;
    reg [2:0] read_hold = 3'd0;
    integer precharge_count = 0;
    integer refresh_count = 0;
    integer mode_count = 0;
    wire [20:0] word_index = {ba, active_row[ba], addr[7:0]};

    assign dq = (read_hold != 3'd0) ? read_data : 32'bz;

    always @(posedge clk) begin
        if (read_hold != 3'd0)
            read_hold <= read_hold - 3'd1;

        if (cke && !cs_n) begin
            case ({ras_n, cas_n, we_n})
                3'b011: active_row[ba] <= addr;
                3'b101: begin
                    read_data <= words[word_index];
                    read_hold <= 3'd4;
                end
                3'b100: begin
                    if (!dqm[3]) words[word_index][31:24] <= dq[31:24];
                    if (!dqm[2]) words[word_index][23:16] <= dq[23:16];
                    if (!dqm[1]) words[word_index][15:8] <= dq[15:8];
                    if (!dqm[0]) words[word_index][7:0] <= dq[7:0];
                end
                3'b010: precharge_count <= precharge_count + 1;
                3'b001: refresh_count <= refresh_count + 1;
                3'b000: mode_count <= mode_count + 1;
                default: ;
            endcase
        end
    end
endmodule
