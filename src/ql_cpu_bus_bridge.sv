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
    output reg         cpu_dtack_n,

    output reg         system_req,
    output reg         system_we,
    output reg  [21:0] system_addr,
    output reg  [1:0]  system_ds,
    output reg  [15:0] system_wdata,
    input  wire        system_ready,
    input  wire        system_data_valid,
    input  wire [15:0] system_data
);

    localparam [1:0] ST_IDLE        = 2'd0;
    localparam [1:0] ST_WAIT_ACCEPT = 2'd1;
    localparam [1:0] ST_WAIT_DATA   = 2'd2;
    localparam [1:0] ST_ACK         = 2'd3;

    reg [1:0] state;
    reg cycle_is_write;

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            cycle_is_write <= 1'b0;
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
                    if (!cpu_as_n && (!cpu_uds_n || !cpu_lds_n)) begin
                        cycle_is_write <= !cpu_rw;
                        system_we <= !cpu_rw;
                        system_addr <= cpu_addr[22:1];
                        system_ds <= {cpu_uds_n, cpu_lds_n};
                        system_wdata <= cpu_data_out;
                        system_req <= 1'b1;
                        state <= ST_WAIT_ACCEPT;
                    end
                end

                ST_WAIT_ACCEPT: begin
                    if (system_ready) begin
                        system_req <= 1'b0;
                        if (cycle_is_write) begin
                            cpu_dtack_n <= 1'b0;
                            state <= ST_ACK;
                        end else begin
                            state <= ST_WAIT_DATA;
                        end
                    end
                end

                ST_WAIT_DATA: begin
                    if (system_data_valid) begin
                        cpu_data_in <= system_data;
                        cpu_dtack_n <= 1'b0;
                        state <= ST_ACK;
                    end
                end

                default: begin
                    if (cpu_as_n) begin
                        cpu_dtack_n <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
