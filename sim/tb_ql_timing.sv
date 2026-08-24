`timescale 1ns/1ps

module tb_ql_timing;
    reg clk_sys = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b1;
    reg ce_bus_p = 1'b1;
    reg vblank = 1'b0;
    reg cpu_uds = 1'b0;
    reg cpu_lds = 1'b0;
    reg cpu_rw = 1'b1;
    reg cpu_uncontended = 1'b0;
    wire ram_delay_dtack;

    always #5 clk_sys = ~clk_sys;

    ql_timing dut (
        .clk_sys(clk_sys),
        .reset(reset),
        .enable(enable),
        .ce_bus_p(ce_bus_p),
        .vblank(vblank),
        .cpu_uds(cpu_uds),
        .cpu_lds(cpu_lds),
        .cpu_rw(cpu_rw),
        .cpu_uncontended(cpu_uncontended),
        .ram_delay_dtack(ram_delay_dtack)
    );

    task automatic start_byte_access(input reg uncontended);
        begin
            cpu_uncontended = uncontended;
            cpu_uds = 1'b1;
            @(posedge clk_sys);
            #1;
            if (!ram_delay_dtack)
                $fatal(1, "Every 68008 access must begin with a timing delay");
        end
    endtask

    task automatic end_access;
        begin
            cpu_uds = 1'b0;
            @(posedge clk_sys);
            #1;
        end
    endtask

    integer waited;
    initial begin
        repeat (2) @(posedge clk_sys);
        reset = 1'b0;

        // Enter the middle of an active-display memory chunk, where the
        // original ZX8301 keeps its internal DRAM bus for video fetches.
        repeat (3) @(posedge clk_sys);
        #1;

        start_byte_access(1'b0);
        waited = 0;
        while (ram_delay_dtack && waited < 20) begin
            @(posedge clk_sys);
            #1;
            waited = waited + 1;
        end
        if (waited < 5)
            $fatal(1, "Base 128 KiB RAM did not wait for a video slot (%0d cycles)", waited);
        end_access();

        // Expansion RAM, ROM and I/O must not inherit the ZX8301 video-slot
        // wait, even when the current active-display chunk is busy.
        repeat (3) @(posedge clk_sys);
        #1;
        start_byte_access(1'b1);
        waited = 0;
        while (ram_delay_dtack && waited < 20) begin
            @(posedge clk_sys);
            #1;
            waited = waited + 1;
        end
        if (waited != 1)
            $fatal(1, "Uncontended access waited %0d cycles instead of one", waited);
        end_access();

        $display("PASS: ZX8301 contention is restricted to internal QL RAM");
        $finish;
    end
endmodule
