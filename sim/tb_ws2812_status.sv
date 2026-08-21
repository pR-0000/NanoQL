`timescale 1ns/1ps

module tb_ws2812_status;
    reg clk_27m = 1'b0;
    reg reset = 1'b1;
    reg caps_lock_active = 1'b1;
    wire data_out;

    ws2812_status dut (
        .clk_27m(clk_27m),
        .reset(reset),
        .caps_lock_active(caps_lock_active),
        .data_out(data_out)
    );

    always #18.5185 clk_27m = ~clk_27m;

    task check_frame;
        input caps_expected;
        integer bit_number;
        time rise_time;
        time high_time;
        reg long_bit;
        begin
            for (bit_number = 0; bit_number < 24; bit_number = bit_number + 1) begin
                @(posedge data_out);
                rise_time = $time;
                @(negedge data_out);
                high_time = $time - rise_time;
                long_bit = high_time > 500;
                if (high_time < 350 || high_time > 950) begin
                    $error("Invalid WS2812 high pulse: %0t ns", high_time);
                    $fatal;
                end
                if (long_bit != (caps_expected &&
                    ((bit_number == 2) || (bit_number == 3)))) begin
                    $error("Unexpected WS2812 bit %0d in Caps=%0d frame", bit_number,
                           caps_expected);
                    $fatal;
                end
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk_27m);
        reset = 1'b0;
        check_frame(1'b1);

        caps_lock_active = 1'b0;
        check_frame(1'b0);

        $display("PASS: WS2812 shows green for Caps Lock and black otherwise");
        $finish;
    end
endmodule
