`timescale 1ns/1ps

module tb_ql_video_snapshot;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b1;
    reg native_frame = 1'b0;
    reg membase = 1'b0;
    reg scanout_buffer_select = 1'b0;
    reg ready = 1'b1;
    reg data_valid = 1'b0;
    reg [15:0] rdata = 16'd0;
    reg write_done = 1'b0;

    wire snapshot_valid;
    wire snapshot_buffer_select;
    wire [21:0] snapshot_base;
    wire req;
    wire we;
    wire [21:0] addr;
    wire [1:0] ds;
    wire [15:0] wdata;

    integer write_count = 0;
    always #5 clk = ~clk;

    ql_video_snapshot #(.FRAME_WORDS(15'd4)) dut (
        .clk(clk), .reset(reset), .enable(enable),
        .native_frame(native_frame), .membase(membase),
        .scanout_buffer_select(scanout_buffer_select),
        .snapshot_valid(snapshot_valid),
        .snapshot_buffer_select(snapshot_buffer_select),
        .snapshot_base(snapshot_base),
        .req(req), .we(we), .addr(addr), .ds(ds), .wdata(wdata),
        .ready(ready), .data_valid(data_valid), .rdata(rdata),
        .write_done(write_done)
    );

    always @(posedge clk) begin
        data_valid <= 1'b0;
        write_done <= 1'b0;
        if (req && ready) begin
            if (we) begin
                write_done <= 1'b1;
                write_count <= write_count + 1;
            end else begin
                rdata <= addr[15:0] ^ 16'h5a5a;
                data_valid <= 1'b1;
            end
        end
    end

    task pulse_native_frame;
        begin
            @(negedge clk);
            native_frame = 1'b1;
            @(negedge clk);
            native_frame = 1'b0;
        end
    endtask

    task wait_for_buffer;
        input expected;
        integer timeout;
        begin : wait_block
            timeout = 0;
            while (!snapshot_valid || snapshot_buffer_select != expected) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 300)
                    $fatal(1, "Timed out waiting for snapshot buffer %b", expected);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;

        wait_for_buffer(1'b0);
        if (snapshot_base != 22'h3f0000 || write_count != 4)
            $fatal(1, "Initial snapshot was not published atomically");

        pulse_native_frame();
        wait_for_buffer(1'b1);
        if (snapshot_base != 22'h3f4000 || write_count != 8)
            $fatal(1, "Second snapshot was not published");

        // HDMI still reads buffer 0. A pending capture must not overwrite it.
        pulse_native_frame();
        repeat (40) @(posedge clk);
        if (write_count != 8 || snapshot_buffer_select != 1'b1)
            $fatal(1, "Snapshot buffer was reused before HDMI acknowledgement");

        scanout_buffer_select = 1'b1;
        while (write_count < 9)
            @(posedge clk);
        enable = 1'b0;
        repeat (20) @(posedge clk);
        if (write_count != 9 || snapshot_buffer_select != 1'b1)
            $fatal(1, "Paused copy modified or published an incomplete snapshot");

        enable = 1'b1;
        wait_for_buffer(1'b0);
        if (write_count != 13)
            $fatal(1, "Paused capture did not restart from a complete frame");

        $display("PASS: atomic snapshots, pause/restart, and reuse handshake");
        $finish;
    end
endmodule
