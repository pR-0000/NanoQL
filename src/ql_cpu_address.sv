module ql_cpu_address(
    input  wire [23:1] word_addr,
    input  wire        uds_n,
    input  wire        lds_n,
    output wire [23:0] byte_addr
);

    // The base 128 KiB QL wraps its decoded address space every 256 KiB.
    assign byte_addr = {word_addr, uds_n && !lds_n} & 24'h03ffff;

endmodule
