module ql_cpu_address(
    input  wire [23:1] word_addr,
    input  wire        uds_n,
    input  wire        lds_n,
    input  wire [1:0]  ram_config,
    output wire [23:0] byte_addr
);

    // Match QL_MiSTer's address masks: the unexpanded machine decodes 256 KiB,
    // the 640/896 KiB configurations decode 1 MiB, and mode 3 is reserved for
    // the future 4 MiB Gold Card implementation.
    wire [23:0] address_mask = (ram_config == 2'd0) ? 24'h03ffff :
                               (ram_config == 2'd3) ? 24'h7fffff :
                                                     24'h0fffff;
    wire [23:0] raw_byte_addr = {word_addr, uds_n && !lds_n};
    // The base QL mirrors its local address space through 0x3ffff, but the
    // expansion connector at 0xc0000-0xfffff must remain visible even with
    // no RAM expansion installed. QSound uses the first 16 KiB slot there.
    wire expansion_slot = (raw_byte_addr[23:20] == 4'd0) &&
                          (raw_byte_addr[19:18] == 2'b11);
    assign byte_addr = expansion_slot ? raw_byte_addr :
                                             (raw_byte_addr & address_mask);

endmodule
