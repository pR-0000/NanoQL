module ql_boot_rom(
    input  wire [14:0] word_addr,
    output wire [15:0] data,
    output wire        is_diagnostic,
    output wire        is_dynamic
);

    // The SD-ROM build serves this address range from SDRAM after loading.
    assign data = 16'hffff;
    assign is_diagnostic = 1'b0;
    assign is_dynamic = 1'b1;

endmodule
