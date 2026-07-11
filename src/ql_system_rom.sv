module ql_boot_rom(
    input  wire [14:0] word_addr,
    output reg  [15:0] data,
    output wire        is_diagnostic,
    output wire        is_dynamic
);

    assign is_diagnostic = 1'b0;
    assign is_dynamic = 1'b0;

    reg [15:0] rom [0:32767];

    initial begin
        $readmemh("src/rom/ql_system_rom.hex", rom);
    end

    always @(*)
        data = rom[word_addr];

endmodule
