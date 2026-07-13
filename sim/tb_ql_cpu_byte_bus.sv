`timescale 1ns/1ps

module tb_ql_cpu_byte_bus;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    wire [23:0] cpu_addr;
    wire [15:0] cpu_data_out;
    wire [15:0] cpu_data_in;
    wire cpu_as_n;
    wire cpu_rw;
    wire cpu_uds_n;
    wire cpu_lds_n;
    wire cpu_dtack_n;
    wire [2:0] cpu_fc;
    wire ce_bus_p;
    wire ce_bus_n;

    wire system_req;
    wire system_we;
    wire [21:0] system_addr;
    wire [1:0] system_ds;
    wire [15:0] system_wdata;
    wire system_ready;
    reg system_data_valid = 1'b0;
    reg [15:0] system_data = 16'd0;
    reg system_write_done = 1'b0;

    reg pending = 1'b0;
    reg pending_we;
    reg [21:0] pending_addr;
    reg [1:0] pending_ds;
    reg [15:0] pending_wdata;
    reg [15:0] ram [0:65535];
    integer cycles;

    assign system_ready = !pending;

    ql_cpu_fx68k cpu (
        .clk(clk), .reset(reset), .enable(1'b1),
        .cpu_addr(cpu_addr), .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in), .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw), .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n), .cpu_dtack_n(cpu_dtack_n),
        .cpu_ipl_n(3'b111), .cpu_fc(cpu_fc),
        .ce_bus_p(ce_bus_p), .ce_bus_n(ce_bus_n)
    );

    ql_cpu_bus_bridge bridge (
        .clk(clk), .reset(reset),
        .cpu_addr(cpu_addr), .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in), .cpu_as_n(cpu_as_n),
        .cpu_rw(cpu_rw), .cpu_uds_n(cpu_uds_n),
        .cpu_lds_n(cpu_lds_n), .cpu_iack(cpu_fc == 3'b111),
        .cpu_dtack_n(cpu_dtack_n), .timing_delay(1'b0),
        .ce_bus_p(ce_bus_p), .system_req(system_req),
        .system_we(system_we), .system_addr(system_addr),
        .system_ds(system_ds), .system_wdata(system_wdata),
        .system_ready(system_ready), .system_data_valid(system_data_valid),
        .system_data(system_data), .system_write_done(system_write_done)
    );

    function automatic [15:0] rom_word(input [21:0] addr);
        begin
            case (addr)
                22'h000000: rom_word = 16'h0003;
                22'h000001: rom_word = 16'hff00;
                22'h000002: rom_word = 16'h0000;
                22'h000003: rom_word = 16'h0100;

                // MOVE.B #$54,$20100 ... MOVE.B #$54,$20103
                22'h000080: rom_word = 16'h13fc;
                22'h000081: rom_word = 16'h0054;
                22'h000082: rom_word = 16'h0002;
                22'h000083: rom_word = 16'h0100;
                22'h000084: rom_word = 16'h13fc;
                22'h000085: rom_word = 16'h0045;
                22'h000086: rom_word = 16'h0002;
                22'h000087: rom_word = 16'h0101;
                22'h000088: rom_word = 16'h13fc;
                22'h000089: rom_word = 16'h0053;
                22'h00008a: rom_word = 16'h0002;
                22'h00008b: rom_word = 16'h0102;
                22'h00008c: rom_word = 16'h13fc;
                22'h00008d: rom_word = 16'h0054;
                22'h00008e: rom_word = 16'h0002;
                22'h00008f: rom_word = 16'h0103;

                // Read each byte back through fx68k and copy it to $20110.
                22'h000090: rom_word = 16'h1039;
                22'h000091: rom_word = 16'h0002;
                22'h000092: rom_word = 16'h0100;
                22'h000093: rom_word = 16'h13c0;
                22'h000094: rom_word = 16'h0002;
                22'h000095: rom_word = 16'h0110;
                22'h000096: rom_word = 16'h1039;
                22'h000097: rom_word = 16'h0002;
                22'h000098: rom_word = 16'h0101;
                22'h000099: rom_word = 16'h13c0;
                22'h00009a: rom_word = 16'h0002;
                22'h00009b: rom_word = 16'h0111;
                22'h00009c: rom_word = 16'h1039;
                22'h00009d: rom_word = 16'h0002;
                22'h00009e: rom_word = 16'h0102;
                22'h00009f: rom_word = 16'h13c0;
                22'h0000a0: rom_word = 16'h0002;
                22'h0000a1: rom_word = 16'h0112;
                22'h0000a2: rom_word = 16'h1039;
                22'h0000a3: rom_word = 16'h0002;
                22'h0000a4: rom_word = 16'h0103;
                22'h0000a5: rom_word = 16'h13c0;
                22'h0000a6: rom_word = 16'h0002;
                22'h0000a7: rom_word = 16'h0113;

                // MOVE.W #$a55a,$201fe; BRA.S *
                22'h0000a8: rom_word = 16'h33fc;
                22'h0000a9: rom_word = 16'ha55a;
                22'h0000aa: rom_word = 16'h0002;
                22'h0000ab: rom_word = 16'h01fe;
                22'h0000ac: rom_word = 16'h60fe;
                default: rom_word = 16'h4e71;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        system_data_valid <= 1'b0;
        system_write_done <= 1'b0;

        if (reset) begin
            pending <= 1'b0;
        end else if (pending) begin
            if (pending_we) begin
                if (pending_addr >= 22'h010000) begin
                    if (!pending_ds[1])
                        ram[pending_addr[15:0]][15:8] <= pending_wdata[15:8];
                    if (!pending_ds[0])
                        ram[pending_addr[15:0]][7:0] <= pending_wdata[7:0];
                end
                system_write_done <= 1'b1;
            end else begin
                system_data <= (pending_addr < 22'h008000) ?
                               rom_word(pending_addr) :
                               ram[pending_addr[15:0]];
                system_data_valid <= 1'b1;
            end
            pending <= 1'b0;
        end else if (system_req) begin
            pending <= 1'b1;
            pending_we <= system_we;
            pending_addr <= system_addr;
            pending_ds <= system_ds;
            pending_wdata <= system_wdata;
        end
    end

    initial begin
        ram[16'h0080] = 16'h0000;
        ram[16'h0081] = 16'h0000;
        ram[16'h0088] = 16'h0000;
        ram[16'h0089] = 16'h0000;
        ram[16'h00ff] = 16'h0000;
        repeat (16) @(posedge clk);
        reset = 1'b0;

        cycles = 0;
        while ((ram[16'h00ff] !== 16'ha55a) && cycles < 200000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (cycles == 200000)
            $fatal(1, "fx68k byte-write program timed out");
        if (ram[16'h0080] !== 16'h5445 || ram[16'h0081] !== 16'h5354)
            $fatal(1, "byte writes produced %h %h instead of 5445 5354",
                   ram[16'h0080], ram[16'h0081]);
        if (ram[16'h0088] !== 16'h5445 || ram[16'h0089] !== 16'h5354)
            $fatal(1, "byte reads copied %h %h instead of 5445 5354",
                   ram[16'h0088], ram[16'h0089]);

        $display("PASS: fx68k read and wrote TEST through both byte lanes");
        $finish;
    end
endmodule
