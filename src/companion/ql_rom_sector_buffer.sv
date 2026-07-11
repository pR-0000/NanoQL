module ql_rom_sector_buffer(
    input  wire        clk,
    input  wire        write_enable,
    input  wire [7:0]  write_addr,
    input  wire [15:0] write_data,
    input  wire [7:0]  read_addr,
    output reg  [15:0] read_data
);

    reg [15:0] memory [0:255];

    always @(posedge clk) begin
        if (write_enable)
            memory[write_addr] <= write_data;
        read_data <= memory[read_addr];
    end

endmodule
