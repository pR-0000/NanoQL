module ql_boot_rom(
    input  wire [14:0] word_addr,
    output reg  [15:0] data,
    output wire        is_diagnostic,
    output wire        is_dynamic
);

    assign is_diagnostic = 1'b1;
    assign is_dynamic = 1'b0;

    // Autonomous 68000/SDRAM/video contention diagnostic image.
    always @(*) begin
        case (word_addr)
`include "rom/ql_diagnostic_rom.vh"

            default: data = 16'hffff;
        endcase
    end

endmodule
