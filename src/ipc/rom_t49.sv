module rom_t49(
    input  wire        clock,
    input  wire [10:0] address,
    output reg  [7:0]  q
);

    reg [7:0] rom [0:2047];

    initial begin
        $readmemh("src/ipc/ql_ipc_rom.hex", rom);
    end

    always @(posedge clock)
        q <= rom[address];

endmodule
