`timescale 1ns/1ps

module tb_ql_companion_hid;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg data_strobe = 1'b0;
    reg data_start = 1'b0;
    reg [7:0] data_in = 8'd0;
    reg host_keyboard_azerty = 1'b1;
    reg rom_keyboard_french = 1'b0;
    wire [7:0] data_out;
    wire [63:0] matrix;
    wire key_event;
    wire key_press_event;

    always #5 clk = ~clk;

    ql_companion_hid #(
        .CAPS_PULSE_CYCLES(8),
        .KEY_MIN_HOLD_TICKS(0)
    ) dut (
        .clk(clk),
        .reset(reset),
        .data_strobe(data_strobe),
        .data_start(data_start),
        .data_in(data_in),
        .host_keyboard_azerty(host_keyboard_azerty),
        .rom_keyboard_french(rom_keyboard_french),
        .data_out(data_out),
        .matrix(matrix),
        .key_event(key_event),
        .key_press_event(key_press_event)
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

    task automatic send_caps_state;
        input caps_lock;
        begin
            @(negedge clk);
            data_start = 1'b1;
            data_in = 8'd8;
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            data_start = 1'b0;
            @(negedge clk);
            data_in = {6'd0, caps_lock, 1'b0};
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic send_remote_contact;
        input [7:0] event_byte;
        begin
            @(negedge clk);
            data_start = 1'b1;
            data_in = 8'd6;
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

    task automatic send_usb_idle;
        input caps_lock;
        begin
            @(negedge clk);
            data_start = 1'b1;
            data_in = 8'd7;
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            data_start = 1'b0;
            @(negedge clk);
            data_in = {6'd0, caps_lock, 1'b0};
            data_strobe = 1'b1;
            @(negedge clk);
            data_strobe = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic check_key;
        input [6:0] raw_usage;
        input integer matrix_bit;
        input expected_shift;
        begin
            send_hid({1'b0, raw_usage});
            if (!matrix[matrix_bit])
                $fatal(1, "usage %02x did not set matrix bit %0d",
                       raw_usage, matrix_bit);
            if (matrix[56] != expected_shift)
                $fatal(1, "usage %02x produced wrong shift state",
                       raw_usage);
            send_hid({1'b1, raw_usage});
            repeat (10) @(negedge clk);
            if (matrix[matrix_bit] || matrix[56])
                $fatal(1, "usage %02x did not release cleanly", raw_usage);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset = 1'b0;

        check_key(7'h33, 22, 1'b0); // AZERTY M
        check_key(7'h10, 63, 1'b0); // AZERTY comma
        check_key(7'h36, 31, 1'b0); // AZERTY semicolon
        check_key(7'h37, 31, 1'b1); // AZERTY colon
        check_key(7'h20, 23, 1'b1); // AZERTY quote -> English QL quote contact

        check_key(7'h1e, 7, 1'b1);  // AZERTY & -> English QL Shift+7

        // Shift+3 on AZERTY is the digit 3. Suppress the host Shift contact
        // while presenting the English QL 3 matrix position.
        send_hid(8'h69);
        send_hid(8'h20);
        if (!matrix[33] || matrix[56])
            $fatal(1, "AZERTY Shift+3 did not produce English QL digit 3");
        send_hid(8'ha0);
        if (matrix[33] || !matrix[56])
            $fatal(1, "AZERTY Shift+3 release did not restore host Shift");
        send_hid(8'he9);
        if (matrix[56])
            $fatal(1, "AZERTY Shift release did not clear QL Shift");

        // NanoQL Link addresses QL contacts directly. Contact 63 is comma
        // on an English QL ROM and must not become the M contact (22).
        send_remote_contact(8'd63);
        if (!matrix[63] || matrix[22])
            $fatal(1, "remote comma was mixed with the USB M mapping");
        // A physical USB M may coexist with the remote comma.
        send_hid(7'h33);
        if (!matrix[63] || !matrix[22])
            $fatal(1, "USB and remote matrices are not independent");
        send_remote_contact(8'hbf);
        if (matrix[63] || !matrix[22])
            $fatal(1, "remote release altered the USB keyboard state");
        send_hid(8'hb3);

        // Shift+1 on AZERTY is digit 1, so the source Shift must not reach
        // the English QL while the translated number contact is held.
        send_hid(8'h69);
        send_hid(8'h1e);
        if (!matrix[35] || matrix[56])
            $fatal(1, "AZERTY Shift+1 did not produce English QL digit 1");
        send_hid(8'h9e);
        send_hid(8'he9);

        // Some USB stacks report Shift-up before the ordinary key-up. The
        // stored semantic binding must keep the original QL contact until
        // that ordinary key is actually released.
        send_hid(8'h69);
        send_hid(8'h1e); // AZERTY Shift+1 -> English digit 1
        send_hid(8'he9);
        if (!matrix[35] || matrix[56])
            $fatal(1, "Shift-first release changed a held semantic key");
        send_hid(8'h9e);
        repeat (10) @(negedge clk);
        if (matrix[35] || matrix[56])
            $fatal(1, "stored semantic key did not release cleanly");

        // Letters use the same stored contact and modifier state. This keeps
        // a short physical USB press visible to the IPC and prevents a
        // Shift-up report from changing an uppercase key before key-up.
        send_hid(8'h69);
        send_hid(8'h04); // AZERTY A position -> English QL Q
        send_hid(8'he9);
        if (!matrix[51] || !matrix[56])
            $fatal(1, "Shift-first release changed a held letter");
        send_hid(8'h84);
        repeat (10) @(negedge clk);
        if (matrix[51] || matrix[56])
            $fatal(1, "stored letter did not release cleanly");

        // A PC AZERTY Caps Lock also exposes digits on the number row.
        // This host-layout convenience is separate from the QL IPC's own
        // letter-only Caps Lock behavior.
        // Shift held during Caps must not change the isolated QL code.
        send_hid(8'h69);
        send_caps_state(1'b1);
        if (!matrix[25])
            $fatal(1, "authoritative Caps Lock did not pulse the QL contact");
        if (matrix[56])
            $fatal(1, "Shift leaked into the QL Caps Lock pulse");
        repeat (10) @(negedge clk);
        if (!matrix[56] || matrix[25])
            $fatal(1, "Caps pulse did not restore the held Shift state");
        send_hid(8'he9);
        send_hid(8'h39);
        send_hid(8'hb9);
        send_usb_idle(1'b1);
        if (matrix[25])
            $fatal(1, "stable Caps Lock snapshot did not release QL contact");
        send_hid(8'h1e);
        if (!matrix[35] || matrix[56])
            $fatal(1, "AZERTY Caps Lock+1 did not produce English QL digit 1");
        send_hid(8'h9e);
        send_usb_idle(1'b1);
        send_hid(8'h20);
        if (!matrix[33] || matrix[56])
            $fatal(1, "USB idle snapshot incorrectly cleared AZERTY Caps Lock");
        send_hid(8'ha0);
        // With PC Caps Lock active, Shift restores the AZERTY punctuation
        // layer instead of leaving the number layer selected.
        send_hid(8'h69);
        send_hid(8'h1e);
        if (!matrix[7] || !matrix[56] || matrix[35])
            $fatal(1, "AZERTY Caps+Shift+1 did not produce ampersand");
        send_hid(8'h9e);
        send_hid(8'he9);
        send_caps_state(1'b0);
        if (!matrix[25])
            $fatal(1, "Caps Lock release did not pulse the QL contact");
        send_hid(8'h39);
        send_hid(8'hb9);
        send_usb_idle(1'b0);

        // Verify same-layout French punctuation as well as an AltGr symbol.
        rom_keyboard_french = 1'b1;
        check_key(7'h36, 18, 1'b0); // AZERTY semicolon -> French QL semicolon
        send_hid(8'h6e);            // right Alt / AltGr
        send_hid(8'h27);            // AltGr+0 -> @
        if (!matrix[50] || !matrix[57] || matrix[58])
            $fatal(1, "AZERTY AltGr+0 did not produce French QL Ctrl+6 (@)");
        send_hid(8'ha7);
        send_hid(8'hee);
        if (matrix[50] || matrix[57] || matrix[58])
            $fatal(1, "AZERTY AltGr+0 did not release cleanly");

        // An authoritative idle report repairs any missed physical-key
        // release without clearing the independent remote matrix.
        send_hid(8'h08);             // physical USB E
        send_remote_contact(8'h3f);  // remote comma
        if (!matrix[52] || !matrix[63])
            $fatal(1, "keyboard setup for idle recovery failed");
        send_usb_idle(1'b0);
        if (matrix[52] || !matrix[63])
            $fatal(1, "USB idle snapshot did not isolate and clear state");
        send_remote_contact(8'hbf);

        $display("PASS: semantic USB AZERTY punctuation translation");
        $finish;
    end
endmodule
