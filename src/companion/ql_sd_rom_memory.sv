module ql_sd_rom_memory (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        we,
    input  wire [14:0] addr,
    input  wire [15:0] wdata,
    output wire        ready,
    output reg         data_valid,
    output reg  [15:0] data,
    output reg         write_done
);

    // Runtime-loaded 64 KiB QL ROM. The synchronous template maps to Gowin
    // BSRAM while keeping the user ROM outside the generated bitstream.
    reg [15:0] memory [0:32767];
    reg [14:0] read_addr;
    reg read_pending;

    assign ready = !read_pending;

    always @(posedge clk) begin
        if (reset) begin
            read_addr <= 15'd0;
            read_pending <= 1'b0;
            data_valid <= 1'b0;
            data <= 16'hffff;
            write_done <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            write_done <= 1'b0;

            if (read_pending) begin
                data <= memory[read_addr];
                data_valid <= 1'b1;
                read_pending <= 1'b0;
            end else if (req) begin
                if (we) begin
                    memory[addr] <= wdata;
                    write_done <= 1'b1;
                end else begin
                    read_addr <= addr;
                    read_pending <= 1'b1;
                end
            end
        end
    end

endmodule
