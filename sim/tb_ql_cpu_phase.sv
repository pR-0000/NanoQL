`timescale 1ns/1ps

module tb_ql_cpu_phase;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [1:0] cpu_speed = 2'd0;
    wire en_phi1;
    wire en_phi2;
    integer ql_ticks;
    integer fast_ticks;
    integer mhz24_ticks;
    integer i;

    always #5 clk = ~clk;

    ql_cpu_phase dut (
        .clk(clk), .reset(reset), .cpu_speed(cpu_speed),
        .en_phi1(en_phi1), .en_phi2(en_phi2)
    );

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;
        ql_ticks = 0;
        for (i = 0; i < 65536; i = i + 1) begin
            @(posedge clk);
            #1;
            if (en_phi1 && en_phi2)
                $fatal(1, "Phi1 and Phi2 overlap in QL mode");
            if (en_phi1 || en_phi2)
                ql_ticks = ql_ticks + 1;
        end
        if (ql_ticks < 20479 || ql_ticks > 20481)
            $fatal(1, "QL mode emitted %0d phase ticks", ql_ticks);

        cpu_speed = 2'd1;
        fast_ticks = 0;
        for (i = 0; i < 96; i = i + 1) begin
            @(posedge clk);
            #1;
            if (en_phi1 && en_phi2)
                $fatal(1, "Phi1 and Phi2 overlap in fast mode");
            if (en_phi1 || en_phi2)
                fast_ticks = fast_ticks + 1;
        end
        if (fast_ticks < 63 || fast_ticks > 65)
            $fatal(1, "16 MHz mode emitted %0d/96 phase ticks", fast_ticks);

        cpu_speed = 2'd2;
        mhz24_ticks = 0;
        for (i = 0; i < 96; i = i + 1) begin
            @(posedge clk);
            #1;
            if (en_phi1 && en_phi2)
                $fatal(1, "Phi1 and Phi2 overlap in 24 MHz mode");
            if (en_phi1 || en_phi2)
                mhz24_ticks = mhz24_ticks + 1;
        end
        if (mhz24_ticks != 96)
            $fatal(1, "24 MHz mode emitted %0d/96 phase ticks", mhz24_ticks);

        cpu_speed = 2'd0;
        repeat (8) begin
            @(posedge clk);
            #1;
            if (en_phi1 && en_phi2)
                $fatal(1, "Phi overlap after live speed change");
        end

        $display("PASS: live QL/16/24 MHz CPU phase selection");
        $finish;
    end
endmodule
