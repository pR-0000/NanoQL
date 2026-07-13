module ql_cpu_bus_bridge(
    input  wire        clk,
    input  wire        reset,

    input  wire [23:0] cpu_addr,
    input  wire [15:0] cpu_data_out,
    output reg  [15:0] cpu_data_in,
    input  wire        cpu_as_n,
    input  wire        cpu_rw,
    input  wire        cpu_uds_n,
    input  wire        cpu_lds_n,
    input  wire        cpu_iack,
    output reg         cpu_dtack_n,
    input  wire        timing_delay,
    input  wire        ce_bus_p,

    output reg         system_req,
    output reg         system_we,
    output reg  [21:0] system_addr,
    output reg  [1:0]  system_ds,
    output reg  [15:0] system_wdata,
    input  wire        system_ready,
    input  wire        system_data_valid,
    input  wire [15:0] system_data,
    input  wire        system_write_done
);

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_WAIT_ACCEPT = 3'd1;
    localparam [2:0] ST_WAIT_DONE   = 3'd2;
    localparam [2:0] ST_ACK         = 3'd3;

    reg [2:0] state;
    reg cycle_is_write;
    reg timing_sampled;
    reg memory_done;

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            cycle_is_write <= 1'b0;
            timing_sampled <= 1'b0;
            memory_done <= 1'b0;
            cpu_data_in <= 16'd0;
            cpu_dtack_n <= 1'b1;
            system_req <= 1'b0;
            system_we <= 1'b0;
            system_addr <= 22'd0;
            system_ds <= 2'b11;
            system_wdata <= 16'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    cpu_dtack_n <= 1'b1;
                    system_req <= 1'b0;

                    // On a real 68000 write cycle, AS is asserted before the
                    // data strobes. Wait for at least one active byte lane so
                    // the write data and mask are both valid.
                    // Interrupt acknowledge is terminated by VPA inside
                    // fx68k. It must not also become a memory transaction.
                    if (!cpu_iack && !cpu_as_n &&
                        (!cpu_uds_n || !cpu_lds_n)) begin
                        cycle_is_write <= !cpu_rw;
                        system_we <= !cpu_rw;
                        system_addr <= cpu_addr[22:1];
                        system_ds <= {cpu_uds_n, cpu_lds_n};
                        system_wdata <= cpu_data_out;
                        timing_sampled <= 1'b0;
                        memory_done <= 1'b0;
                        system_req <= 1'b1;
                        state <= ST_WAIT_ACCEPT;
                    end
                end

                ST_WAIT_ACCEPT: begin
                    if (ce_bus_p)
                        timing_sampled <= 1'b1;
                    if (system_ready) begin
                        system_req <= 1'b0;
                        state <= ST_WAIT_DONE;
                    end
                end

                ST_WAIT_DONE: begin
                    if (ce_bus_p)
                        timing_sampled <= 1'b1;

                    if (!cycle_is_write && system_data_valid) begin
                        cpu_data_in <= system_data;
                        memory_done <= 1'b1;
                    end else if (cycle_is_write && system_write_done) begin
                        memory_done <= 1'b1;
                    end

                    if ((memory_done ||
                         (!cycle_is_write && system_data_valid) ||
                         (cycle_is_write && system_write_done)) &&
                        timing_sampled && !timing_delay) begin
                        cpu_dtack_n <= 1'b0;
                        state <= ST_ACK;
                    end
                end

                default: begin
                    // A read-modify-write cycle (notably TAS) keeps AS low
                    // while releasing both data strobes between its read and
                    // write halves. Release DTACK at that boundary so the
                    // second half becomes a real memory transaction.
                    if (cpu_as_n || (cpu_uds_n && cpu_lds_n)) begin
                        cpu_dtack_n <= 1'b1;
                        timing_sampled <= 1'b0;
                        memory_done <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
