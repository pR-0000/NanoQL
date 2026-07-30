module rom_t49(
    input  wire        clock,
    input  wire [10:0] address,
    output reg  [7:0]  q,
    input  wire        write_enable,
    input  wire [10:0] write_address,
    input  wire [7:0]  write_data
);

    reg [7:0] rom [0:2047];

    always @(posedge clock) begin
        if (write_enable)
            rom[write_address] <= write_data;
        q <= rom[address];
    end

endmodule
