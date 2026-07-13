`timescale 1ns/1ps

module tb_ql_bus_memory;
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

    reg [18:0] client_addr = 19'd0;
    reg client_rd = 1'b0;
    wire client_ready;
    wire client_data_valid;
    wire [15:0] client_data;
    wire init_done;
    wire init_fail;
    wire [31:0] sdram_dq;

    ql_cpu_bus_bridge bridge (
        .clk(clk),
        .reset(reset),
        .cpu_addr(cpu_addr),
        .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in),
        .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw),
        .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n),
        .cpu_iack(1'b0),
        .cpu_dtack_n(cpu_dtack_n),
        .timing_delay(1'b0),
        .ce_bus_p(ce_bus_p),
        .system_req(system_req),
        .system_we(system_we),
        .system_addr(system_addr),
        .system_ds(system_ds),
        .system_wdata(system_wdata),
        .system_ready(system_ready),
        .system_data_valid(system_data_valid),
        .system_data(system_data),
        .system_write_done(system_write_done)
    );

    ql_sdram_memory memory (
        .clk(clk),
        .reset(reset),
        .client_rd(client_rd),
        .client_addr(client_addr),
        .client_ready(client_ready),
        .client_data_valid(client_data_valid),
        .client_data(client_data),
        .system_req(system_req),
        .system_we(system_we),
        .system_addr(system_addr),
        .system_ds(system_ds),
        .system_wdata(system_wdata),
        .system_ready(system_ready),
        .system_data_valid(system_data_valid),
        .system_data(system_data),
        .system_write_done(system_write_done),
        .sdram_clk(),
        .sdram_cke(),
        .sdram_cs_n(),
        .sdram_cas_n(),
        .sdram_ras_n(),
        .sdram_wen_n(),
        .sdram_dq(sdram_dq),
        .sdram_addr(),
        .sdram_ba(),
        .sdram_dqm(),
        .init_done(init_done),
        .init_fail(init_fail)
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

    task automatic video_burst;
        input [18:0] first_address;
        integer issued;
        integer received;
        begin
            issued = 0;
            received = 0;
            client_addr <= first_address;
            client_rd <= 1'b1;
            while (received < 64) begin
                @(posedge clk);
                if (client_rd && client_ready) begin
                    issued = issued + 1;
                    if (issued == 64)
                        client_rd <= 1'b0;
                    else
                        client_addr <= first_address + issued;
                end
                if (client_data_valid)
                    received = received + 1;
            end
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        reset <= 1'b0;
        wait (init_done || init_fail);
        if (init_fail)
            $fatal(1, "SDRAM initialization failed");

        cpu_write(24'h020100, 16'h1234, 1'b0, 1'b0);
        cpu_read_word(24'h020100, 16'h1234);

        cpu_write(24'h020100, 16'hab00, 1'b0, 1'b1);
        cpu_read_word(24'h020100, 16'hab34);

        cpu_write(24'h020100, 16'h00cd, 1'b1, 1'b0);
        cpu_read_word(24'h020100, 16'habcd);

        cpu_write(24'h020102, 16'h7050, 1'b0, 1'b0);
        cpu_write(24'h020104, 16'h5050, 1'b0, 1'b0);
        cpu_read_word(24'h020102, 16'h7050);
        cpu_read_word(24'h020104, 16'h5050);

        // The scanout keeps its request asserted for 64 words. A pending CPU
        // cycle must wait without being lost or acknowledged prematurely.
        fork
            video_burst(19'h10000);
            begin
                repeat (4) @(posedge clk);
                cpu_write(24'h020106, 16'hcafe, 1'b0, 1'b0);
                cpu_read_word(24'h020106, 16'hcafe);
            end
        join

        $display("PASS: QL CPU bridge, atomic byte writes, and video contention");
        $finish;
    end
endmodule

module sdram (
    output wire sd_clk,
    output wire sd_cke,
    inout wire [31:0] sd_data,
    output wire [12:0] sd_addr,
    output wire [3:0] sd_dqm,
    output wire [1:0] sd_ba,
    output wire sd_cs,
    output wire sd_we,
    output wire sd_ras,
    output wire sd_cas,
    input wire clk,
    input wire reset_n,
    output wire ready,
    input wire refresh,
    input wire [15:0] din,
    output reg [15:0] dout,
    input wire [21:0] addr,
    input wire [1:0] ds,
    input wire cs,
    input wire we
);
    reg [15:0] words [0:131071];
    reg cs_d = 1'b0;

    assign ready = reset_n;
    assign sd_clk = clk;
    assign sd_cke = 1'b1;
    assign sd_data = 32'bz;
    assign sd_addr = 13'd0;
    assign sd_dqm = 4'hf;
    assign sd_ba = 2'd0;
    assign sd_cs = 1'b1;
    assign sd_we = 1'b1;
    assign sd_ras = 1'b1;
    assign sd_cas = 1'b1;

    always @(posedge clk) begin
        cs_d <= cs;
        if (!reset_n) begin
            cs_d <= 1'b0;
            dout <= 16'd0;
        end else if (cs && !cs_d && !refresh) begin
            if (we) begin
                if (!ds[1])
                    words[addr[16:0]][15:8] <= din[15:8];
                if (!ds[0])
                    words[addr[16:0]][7:0] <= din[7:0];
            end else begin
                dout <= words[addr[16:0]];
            end
        end
    end
endmodule
