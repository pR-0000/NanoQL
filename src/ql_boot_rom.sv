module ql_boot_rom(
    input  wire [14:0] word_addr,
    output reg  [15:0] data
);

    // Minimal 68000 diagnostic image. The full 48 KiB QL ROM will replace it.
    always @(*) begin
        case (word_addr)
            // Initial supervisor stack pointer: 0x00028000.
            15'h0000: data = 16'h0002;
            15'h0001: data = 16'h8000;

            // Initial program counter: 0x00000100.
            15'h0002: data = 16'h0000;
            15'h0003: data = 16'h0100;

            // Verify mode-4 VRAM, read ZX8302 status, draw an 8x8 mode-8
            // marker, then select screen 1/mode 8 through ZX8301 MC_STAT.
            15'h0080: data = 16'h33fc;
            15'h0081: data = 16'h00ff;
            15'h0082: data = 16'h0002;
            15'h0083: data = 16'h4100;
            15'h0084: data = 16'h3039;
            15'h0085: data = 16'h0002;
            15'h0086: data = 16'h4100;
            15'h0087: data = 16'h0c40;
            15'h0088: data = 16'h00ff;
            15'h0089: data = 16'h6658;

            // move.w 0x00018020,d1
            15'h008a: data = 16'h3239;
            15'h008b: data = 16'h0001;
            15'h008c: data = 16'h8020;

            // Eight red mode-8 words on consecutive 128-byte scanlines.
            15'h008d: data = 16'h33fc;
            15'h008e: data = 16'h00aa;
            15'h008f: data = 16'h0002;
            15'h0090: data = 16'hc100;
            15'h0091: data = 16'h33fc;
            15'h0092: data = 16'h00aa;
            15'h0093: data = 16'h0002;
            15'h0094: data = 16'hc180;
            15'h0095: data = 16'h33fc;
            15'h0096: data = 16'h00aa;
            15'h0097: data = 16'h0002;
            15'h0098: data = 16'hc200;
            15'h0099: data = 16'h33fc;
            15'h009a: data = 16'h00aa;
            15'h009b: data = 16'h0002;
            15'h009c: data = 16'hc280;
            15'h009d: data = 16'h33fc;
            15'h009e: data = 16'h00aa;
            15'h009f: data = 16'h0002;
            15'h00a0: data = 16'hc300;
            15'h00a1: data = 16'h33fc;
            15'h00a2: data = 16'h00aa;
            15'h00a3: data = 16'h0002;
            15'h00a4: data = 16'hc380;
            15'h00a5: data = 16'h33fc;
            15'h00a6: data = 16'h00aa;
            15'h00a7: data = 16'h0002;
            15'h00a8: data = 16'hc400;
            15'h00a9: data = 16'h33fc;
            15'h00aa: data = 16'h00aa;
            15'h00ab: data = 16'h0002;
            15'h00ac: data = 16'hc480;

            // move.b #0x88,0x00018063
            15'h00ad: data = 16'h13fc;
            15'h00ae: data = 16'h0088;
            15'h00af: data = 16'h0001;
            15'h00b0: data = 16'h8063;

            // Report success and stop in a short loop.
            15'h00b1: data = 16'h33fc;
            15'h00b2: data = 16'ha55a;
            15'h00b3: data = 16'h0002;
            15'h00b4: data = 16'hfffc;
            15'h00b5: data = 16'h60fe;

            // Failure path selected by the earlier BNE.
            15'h00b6: data = 16'h33fc;
            15'h00b7: data = 16'hdead;
            15'h00b8: data = 16'h0002;
            15'h00b9: data = 16'hfffc;
            15'h00ba: data = 16'h60fe;

            default: data = 16'hffff;
        endcase
    end

endmodule
