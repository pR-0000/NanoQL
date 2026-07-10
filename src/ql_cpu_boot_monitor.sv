module ql_cpu_boot_monitor(
    input  wire        clk,
    input  wire        reset,
    input  wire [23:0] cpu_addr,
    input  wire [15:0] cpu_data_out,
    input  wire        cpu_as_n,
    input  wire        cpu_rw,
    input  wire        cpu_uds_n,
    input  wire        cpu_lds_n,
    input  wire        cpu_dtack_n,
    output reg         boot_done,
    output reg         boot_fail
);

    localparam [23:0] STATUS_ADDR = 24'h02fffc;
    localparam [23:0] MC_STAT_ADDR = 24'h018062;
    localparam [23:0] ZX8302_STATUS_ADDR = 24'h018020;
    localparam [15:0] STATUS_OK = 16'ha55a;
    localparam [15:0] STATUS_FAIL = 16'hdead;

    reg mc_stat_seen;
    reg zx8302_read_seen;
    reg irq_ack_seen;
    wire completed_write = !cpu_as_n && !cpu_rw && !cpu_dtack_n;
    wire completed_read = !cpu_as_n && cpu_rw && !cpu_dtack_n;
    wire completed_word_write = completed_write &&
                                !cpu_uds_n && !cpu_lds_n;

    always @(posedge clk) begin
        if (reset) begin
            boot_done <= 1'b0;
            boot_fail <= 1'b0;
            mc_stat_seen <= 1'b0;
            zx8302_read_seen <= 1'b0;
            irq_ack_seen <= 1'b0;
        end else if (completed_read && (cpu_addr == ZX8302_STATUS_ADDR) &&
                     !cpu_uds_n && !cpu_lds_n) begin
            zx8302_read_seen <= 1'b1;
        end else if (completed_write && (cpu_addr == MC_STAT_ADDR) &&
                     cpu_uds_n && !cpu_lds_n) begin
            if (cpu_data_out[7:0] == 8'h88)
                mc_stat_seen <= 1'b1;
            else
                boot_fail <= 1'b1;
        end else if (completed_write &&
                     (cpu_addr == ZX8302_STATUS_ADDR) &&
                     cpu_uds_n && !cpu_lds_n) begin
            if (cpu_data_out[7:0] == 8'h08)
                irq_ack_seen <= 1'b1;
            else
                boot_fail <= 1'b1;
        end else if (completed_word_write && (cpu_addr == STATUS_ADDR)) begin
            if (cpu_data_out == STATUS_OK) begin
                if (mc_stat_seen && zx8302_read_seen && irq_ack_seen)
                    boot_done <= 1'b1;
                else
                    boot_fail <= 1'b1;
            end
            else if (cpu_data_out == STATUS_FAIL)
                boot_fail <= 1'b1;
            else
                boot_fail <= 1'b1;
        end
    end

endmodule
