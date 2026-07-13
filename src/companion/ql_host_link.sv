// NanoQL Link: bounded SPI commands for direct 68000 RAM upload and start.
// Byte addresses and payload data use the 68000's big-endian convention.
module ql_host_link (
    input  wire        clk,
    input  wire        reset,
    input  wire        data_strobe,
    input  wire        data_start,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,

    input  wire        sdram_ready,
    output reg         mem_req,
    output wire        mem_we,
    output reg  [21:0] mem_addr,
    output reg  [1:0]  mem_ds,
    output reg  [15:0] mem_wdata,
    input  wire        mem_ready,
    input  wire        mem_write_done,

    output reg         cpu_hold,
    output reg         boot_vectors_active,
    output reg  [31:0] boot_ssp,
    output reg  [31:0] boot_pc,
    output reg         restart_pulse
);

    localparam [7:0] CMD_STATUS = 8'h00;
    localparam [7:0] CMD_HOLD   = 8'h01;
    localparam [7:0] CMD_WRITE  = 8'h02;
    localparam [7:0] CMD_EXEC   = 8'h03;
    localparam [7:0] CMD_QDOS   = 8'h04;

    localparam [1:0] WR_IDLE = 2'd0;
    localparam [1:0] WR_REQ  = 2'd1;
    localparam [1:0] WR_WAIT = 2'd2;

    reg [7:0] command;
    reg [3:0] field_index;
    reg [23:0] packet_addr;
    reg [3:0] packet_length;
    reg [3:0] payload_count;
    reg [7:0] payload [0:7];
    reg [1:0] write_state;
    reg [3:0] write_index;
    reg [23:0] write_addr;
    reg protocol_error;
    reg [3:0] status_index;
    reg [31:0] exec_ssp;
    reg [31:0] exec_pc;

    wire busy = write_state != WR_IDLE;
    wire address_valid = (packet_addr >= 24'h020000) &&
                         (packet_addr <= 24'h03ffff);
    assign mem_we = 1'b1;

    function [7:0] status_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: status_byte = 8'h4e; // N
                4'd1: status_byte = 8'h51; // Q
                4'd2: status_byte = 8'h4c; // L
                4'd3: status_byte = 8'h31; // protocol 1
                4'd4: status_byte = {3'b000, boot_vectors_active,
                                     cpu_hold, protocol_error, busy,
                                     sdram_ready};
                default: status_byte = 8'h00;
            endcase
        end
    endfunction

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            data_out <= 8'h00;
            command <= CMD_STATUS;
            field_index <= 4'd0;
            packet_addr <= 24'd0;
            packet_length <= 4'd0;
            payload_count <= 4'd0;
            write_state <= WR_IDLE;
            write_index <= 4'd0;
            write_addr <= 24'd0;
            protocol_error <= 1'b0;
            status_index <= 4'd0;
            exec_ssp <= 32'd0;
            exec_pc <= 32'd0;
            mem_req <= 1'b0;
            mem_addr <= 22'd0;
            mem_ds <= 2'b00;
            mem_wdata <= 16'd0;
            cpu_hold <= 1'b0;
            boot_vectors_active <= 1'b0;
            boot_ssp <= 32'h0003fff0;
            boot_pc <= 32'h00030000;
            restart_pulse <= 1'b0;
            for (i = 0; i < 8; i = i + 1)
                payload[i] <= 8'd0;
        end else begin
            restart_pulse <= 1'b0;

            case (write_state)
                WR_REQ: begin
                    mem_req <= 1'b1;
                    mem_addr <= write_addr[22:1];
                    if (!write_addr[0]) begin
                        mem_ds <= 2'b01;
                        mem_wdata <= {payload[write_index], 8'h00};
                    end else begin
                        mem_ds <= 2'b10;
                        mem_wdata <= {8'h00, payload[write_index]};
                    end
                    if (mem_req && mem_ready) begin
                        mem_req <= 1'b0;
                        write_state <= WR_WAIT;
                    end
                end

                WR_WAIT: begin
                    if (mem_write_done) begin
                        if (write_index + 4'd1 >= packet_length) begin
                            write_state <= WR_IDLE;
                            write_index <= 4'd0;
                        end else begin
                            write_index <= write_index + 4'd1;
                            write_addr <= write_addr + 24'd1;
                            write_state <= WR_REQ;
                        end
                    end
                end

                default: mem_req <= 1'b0;
            endcase

            if (data_strobe) begin
                if (data_start) begin
                    command <= data_in;
                    field_index <= 4'd0;
                    payload_count <= 4'd0;
                    status_index <= 4'd0;
                    data_out <= status_byte(4'd0);

                    case (data_in)
                        CMD_HOLD: begin
                            cpu_hold <= 1'b1;
                            boot_vectors_active <= 1'b0;
                            protocol_error <= 1'b0;
                        end
                        CMD_QDOS: begin
                            cpu_hold <= 1'b0;
                            boot_vectors_active <= 1'b0;
                            protocol_error <= 1'b0;
                            restart_pulse <= 1'b1;
                        end
                        CMD_STATUS: begin
                            status_index <= 4'd1;
                            data_out <= status_byte(4'd0);
                        end
                        default: begin end
                    endcase
                end else begin
                    field_index <= field_index + 4'd1;

                    if (command == CMD_STATUS) begin
                        data_out <= status_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_WRITE) begin
                        case (field_index)
                            4'd0: packet_addr[23:16] <= data_in;
                            4'd1: packet_addr[15:8] <= data_in;
                            4'd2: packet_addr[7:0] <= data_in;
                            4'd3: begin
                                packet_length <= data_in[3:0];
                                if ((data_in == 8'd0) || (data_in > 8'd8))
                                    protocol_error <= 1'b1;
                            end
                            default: begin
                                if (payload_count < 4'd8) begin
                                    payload[payload_count] <= data_in;
                                    payload_count <= payload_count + 4'd1;
                                end
                                if ((payload_count + 4'd1 == packet_length) &&
                                    (packet_length != 4'd0)) begin
                                    if (!cpu_hold || busy || !sdram_ready ||
                                        !address_valid ||
                                        ({1'b0, packet_addr} + packet_length >
                                         25'h0040000)) begin
                                        protocol_error <= 1'b1;
                                    end else begin
                                        write_addr <= packet_addr;
                                        write_index <= 4'd0;
                                        write_state <= WR_REQ;
                                    end
                                end
                            end
                        endcase
                    end else if (command == CMD_EXEC) begin
                        case (field_index)
                            4'd0: exec_ssp[31:24] <= data_in;
                            4'd1: exec_ssp[23:16] <= data_in;
                            4'd2: exec_ssp[15:8] <= data_in;
                            4'd3: exec_ssp[7:0] <= data_in;
                            4'd4: exec_pc[31:24] <= data_in;
                            4'd5: exec_pc[23:16] <= data_in;
                            4'd6: exec_pc[15:8] <= data_in;
                            4'd7: begin
                                exec_pc[7:0] <= data_in;
                                if (!cpu_hold || busy || !sdram_ready ||
                                    (exec_ssp < 32'h00020000) ||
                                    (exec_ssp > 32'h00040000) ||
                                    ({exec_pc[31:8], data_in} < 32'h00020000) ||
                                    ({exec_pc[31:8], data_in} > 32'h0003ffff) ||
                                    exec_ssp[0] || data_in[0]) begin
                                    protocol_error <= 1'b1;
                                end else begin
                                    boot_ssp <= exec_ssp;
                                    boot_pc <= {exec_pc[31:8], data_in};
                                    boot_vectors_active <= 1'b1;
                                    cpu_hold <= 1'b0;
                                    protocol_error <= 1'b0;
                                    restart_pulse <= 1'b1;
                                end
                            end
                            default: begin end
                        endcase
                    end
                end
            end
        end
    end

endmodule
