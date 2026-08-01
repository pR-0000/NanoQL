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

    ql_companion_hid dut (
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
        check_key(7'h20, 40, 1'b1); // AZERTY quote -> English QL Shift+9

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

        $display("PASS: AZERTY punctuation and English QL quote translation");
        $finish;
    end
endmodule
