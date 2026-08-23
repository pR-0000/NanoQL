`timescale 1ns/1ps

module tb_ql_companion_hid_mod_delay;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg data_strobe = 1'b0;
    reg data_start = 1'b0;
    reg [7:0] data_in = 8'd0;
    wire [63:0] matrix;

    always #5 clk = ~clk;

    ql_companion_hid #(
        .KEY_MIN_HOLD_TICKS(8),
        .KEY_MOD_DELAY_TICKS(2)
    ) dut (
        .clk(clk),
        .reset(reset),
        .data_strobe(data_strobe),
        .data_start(data_start),
        .data_in(data_in),
        .host_keyboard_azerty(1'b1),
        .rom_keyboard_french(1'b1),
        .data_out(),
        .matrix(matrix),
        .key_event(),
        .key_press_event(),
        .caps_lock_active()
    );

    task automatic send_hid;
        input [7:0] event_byte;
        begin
            @(negedge clk);
            data_start = 1'b1;
            data_in = 8'd1;
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            data_start = 1'b0;
            @(negedge clk);
            data_in = event_byte;
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic wait_delay_tick;
        begin
            repeat (32770) @(negedge clk);
        end
    endtask

    task automatic check_delayed_key;
        input [6:0] raw_usage;
        input integer contact;
        input expected_ctrl;
        integer slot;
        integer index;
        begin
            send_hid({1'b0, raw_usage});
            slot = -1;
            for (index = 0; index < 6; index = index + 1)
                if (dut.semantic_valid[index] &&
                    dut.semantic_raw[index] == raw_usage)
                    slot = index;
            if (slot < 0)
                $fatal(1, "semantic key slot was not allocated");
            if (!matrix[56] || (matrix[57] != expected_ctrl))
                $fatal(1, "generated modifiers were not established first");
            if (matrix[contact])
                $fatal(1, "matrix contact appeared before its modifiers");
            wait_delay_tick();
            if (matrix[contact] || dut.semantic_hold[slot] != 7'd9)
                $fatal(1, "key hold elapsed during modifier setup");
            wait_delay_tick();
            if (!matrix[contact] || !matrix[56] ||
                (matrix[57] != expected_ctrl))
                $fatal(1, "delayed matrix contact or modifier is missing");
            send_hid({1'b1, raw_usage});
            repeat (10) @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset = 1'b0;

        // French MGF: dollar is QL Shift+4. The PC key itself carries no
        // Shift, so NanoQL must establish a generated Shift before contact 6.
        check_delayed_key(7'h30, 6, 1'b0);

        // French MGF: question mark is Shift+cedilla. A USB report may carry
        // Shift and the key together, so the translated contact is delayed.
        send_hid(8'h69);
        check_delayed_key(7'h10, 61, 1'b0);
        send_hid(8'he9);

        // French MGF: QL code 60 (pound) is Shift+u-grave.
        send_hid(8'h69);
        check_delayed_key(7'h30, 13, 1'b0);
        send_hid(8'he9);

        $display("PASS: generated QL modifiers precede translated contacts");
        $finish;
    end
endmodule
