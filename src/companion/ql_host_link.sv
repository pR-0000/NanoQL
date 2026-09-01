// NanoQL Link: bounded SPI commands for direct 68000 RAM upload and start.
// Byte addresses and payload data use the 68000's big-endian convention.
module ql_host_link #(
    parameter [21:0] ROM_SDRAM_BASE = 22'h3f8000
) (
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
    input  wire        mem_data_valid,
    input  wire [15:0] mem_rdata,

    input  wire [23:0] cpu_addr,
    input  wire        cpu_as_n,
    input  wire        cpu_rw,
    input  wire        cpu_dtack_n,
    input  wire [2:0]  cpu_fc,
    input  wire [7:0]  keyboard_report_count,
    input  wire [7:0]  qlsd_status_flags,
    input  wire [23:0] qlsd_last_lba,
    input  wire [31:0] qlsd_header,
    input  wire [15:0] qlsd_byte_count,
    input  wire [31:0] qlsd_crc32,
    input  wire [63:0] qlsd_sample,
    input  wire [7:0]  mdv_status_flags,
    input  wire [17:0] mdv_byte_position,
    input  wire [8:0]  mdv_current_sector,
    input  wire [1:0]  mdv_buffer_valid,
    input  wire [8:0]  mdv_buffer_sector_0,
    input  wire [8:0]  mdv_buffer_sector_1,
    input  wire [3:0]  mdv_bit_counter,
    input  wire [15:0] mdv_rx_count,
    input  wire [15:0] mdv_rx_missed_count,
    input  wire [7:0]  mdv_rx_xor,
    input  wire [7:0]  mdv_rx_last,
    input  wire [15:0] mdv_cpu_read_count,
    input  wire [7:0]  mdv_cpu_read_xor,
    input  wire [7:0]  mdv_cpu_read_last,
    input  wire [4:0]  mdv_cpu_trace_count,
    input  wire [127:0] mdv_cpu_trace,
    input  wire [9:0]  mdv_data_trace_count,
    input  wire [127:0] mdv_data_trace,
    input  wire [1:0]  cpu_speed,
    input  wire [31:0] cpu_phase_count,
    input  wire        rom_keyboard_french,
    output reg  [4:0]  cpu_debug_reg_select,
    output reg  [4:0]  cpu_debug_bit_select,
    input  wire        cpu_debug_reg_bit,
    input  wire [31:0] cpu_debug_pc,
    input  wire [15:0] cpu_debug_sr,
    input  wire [15:0] cpu_debug_ir,

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
    localparam [7:0] CMD_READ   = 8'h06;
    localparam [7:0] CMD_RESULT = 8'h07;
    localparam [7:0] CMD_QLSD   = 8'h08;
    localparam [7:0] CMD_CPU     = 8'h09;
    localparam [7:0] CMD_MDV      = 8'h0a;
    localparam [7:0] CMD_MDV_TRACE = 8'h0b;
    localparam [7:0] CMD_MDV_DATA_TRACE = 8'h0c;
    localparam [7:0] CMD_RESUME = 8'h0d;
    localparam [7:0] CMD_DEBUG  = 8'h0e;
    localparam [7:0] CMD_DEBUG_RESULT = 8'h0f;
    localparam [7:0] CMD_DEBUG_INFO = 8'h10;

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
    reg transfer_write;
    reg [3:0] result_index;
    reg [7:0] read_payload [0:7];
    reg exec_fetch_seen;
    reg exec_video_write_seen;
    reg hold_pending;
    reg [5:0] debug_capture_count;
    reg [31:0] debug_captured_value;
    reg [31:0] debug_captured_pc;
    reg [15:0] debug_captured_sr;
    reg [15:0] debug_captured_ir;

    wire busy = write_state != WR_IDLE;
    wire ram_address_valid = (packet_addr >= 24'h020000) &&
                             (packet_addr <= 24'h03ffff);
    wire rom_address_valid = packet_addr <= 24'h00ffff;
    wire read_address_valid = ram_address_valid || rom_address_valid;
    assign mem_we = transfer_write;

    function [7:0] status_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: status_byte = 8'h4e; // N
                4'd1: status_byte = 8'h51; // Q
                4'd2: status_byte = 8'h4c; // L
                4'd3: status_byte = 8'h31; // protocol 1
                4'd4: status_byte = {exec_fetch_seen,
                                     exec_video_write_seen, 1'b0,
                                     boot_vectors_active,
                                     cpu_hold, protocol_error, busy,
                                     sdram_ready};
                4'd5: status_byte = keyboard_report_count;
                4'd6: status_byte = qlsd_status_flags;
                4'd7: status_byte = qlsd_last_lba[23:16];
                4'd8: status_byte = qlsd_last_lba[15:8];
                4'd9: status_byte = qlsd_last_lba[7:0];
                4'd10: status_byte = qlsd_header[31:24];
                4'd11: status_byte = qlsd_header[23:16];
                4'd12: status_byte = qlsd_header[15:8];
                4'd13: status_byte = qlsd_header[7:0];
                4'd14: status_byte = qlsd_byte_count[15:8];
                4'd15: status_byte = qlsd_byte_count[7:0];
                default: status_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] qlsd_diag_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: qlsd_diag_byte = 8'h51; // Q
                4'd1: qlsd_diag_byte = 8'h53; // S
                4'd2: qlsd_diag_byte = 8'h44; // D
                4'd3: qlsd_diag_byte = 8'h31; // protocol 1
                4'd4: qlsd_diag_byte = qlsd_crc32[31:24];
                4'd5: qlsd_diag_byte = qlsd_crc32[23:16];
                4'd6: qlsd_diag_byte = qlsd_crc32[15:8];
                4'd7: qlsd_diag_byte = qlsd_crc32[7:0];
                4'd8: qlsd_diag_byte = qlsd_sample[63:56];
                4'd9: qlsd_diag_byte = qlsd_sample[55:48];
                4'd10: qlsd_diag_byte = qlsd_sample[47:40];
                4'd11: qlsd_diag_byte = qlsd_sample[39:32];
                4'd12: qlsd_diag_byte = qlsd_sample[31:24];
                4'd13: qlsd_diag_byte = qlsd_sample[23:16];
                4'd14: qlsd_diag_byte = qlsd_sample[15:8];
                4'd15: qlsd_diag_byte = qlsd_sample[7:0];
                default: qlsd_diag_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] cpu_diag_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: cpu_diag_byte = 8'h43; // C
                4'd1: cpu_diag_byte = 8'h50; // P
                4'd2: cpu_diag_byte = 8'h55; // U
                4'd3: cpu_diag_byte = 8'h31; // protocol 1
                4'd4: cpu_diag_byte = {6'd0, cpu_speed};
                4'd5: cpu_diag_byte = cpu_phase_count[31:24];
                4'd6: cpu_diag_byte = cpu_phase_count[23:16];
                4'd7: cpu_diag_byte = cpu_phase_count[15:8];
                4'd8: cpu_diag_byte = cpu_phase_count[7:0];
                4'd9: cpu_diag_byte = {7'd0, rom_keyboard_french};
                default: cpu_diag_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] mdv_diag_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: mdv_diag_byte = 8'h4d; // M
                4'd1: mdv_diag_byte = 8'h44; // D
                4'd2: mdv_diag_byte = 8'h56; // V
                4'd3: mdv_diag_byte = 8'h33; // protocol 3
                4'd4: mdv_diag_byte = mdv_status_flags;
                4'd5: mdv_diag_byte = {6'd0, mdv_byte_position[17:16]};
                4'd6: mdv_diag_byte = mdv_byte_position[15:8];
                4'd7: mdv_diag_byte = mdv_byte_position[7:0];
                4'd8: mdv_diag_byte = mdv_rx_count[15:8];
                4'd9: mdv_diag_byte = mdv_rx_count[7:0];
                4'd10: mdv_diag_byte = mdv_cpu_read_count[15:8];
                4'd11: mdv_diag_byte = mdv_cpu_read_count[7:0];
                4'd12: mdv_diag_byte = mdv_rx_missed_count[15:8];
                4'd13: mdv_diag_byte = mdv_rx_missed_count[7:0];
                4'd14: mdv_diag_byte = mdv_rx_last;
                4'd15: mdv_diag_byte = mdv_cpu_read_last;
                default: mdv_diag_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] mdv_trace_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: mdv_trace_byte = 8'h4d; // M
                4'd1: mdv_trace_byte = 8'h54; // T
                4'd2: mdv_trace_byte = {3'd0, mdv_cpu_trace_count};
                4'd3: mdv_trace_byte = mdv_cpu_trace[127:120];
                4'd4: mdv_trace_byte = mdv_cpu_trace[119:112];
                4'd5: mdv_trace_byte = mdv_cpu_trace[111:104];
                4'd6: mdv_trace_byte = mdv_cpu_trace[103:96];
                4'd7: mdv_trace_byte = mdv_cpu_trace[95:88];
                4'd8: mdv_trace_byte = mdv_cpu_trace[87:80];
                4'd9: mdv_trace_byte = mdv_cpu_trace[79:72];
                4'd10: mdv_trace_byte = mdv_cpu_trace[71:64];
                4'd11: mdv_trace_byte = mdv_cpu_trace[63:56];
                4'd12: mdv_trace_byte = mdv_cpu_trace[55:48];
                4'd13: mdv_trace_byte = mdv_cpu_trace[47:40];
                4'd14: mdv_trace_byte = mdv_cpu_trace[39:32];
                4'd15: mdv_trace_byte = mdv_cpu_trace[31:24];
                default: mdv_trace_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] mdv_data_trace_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: mdv_data_trace_byte = 8'h4d; // M
                4'd1: mdv_data_trace_byte = 8'h42; // B
                4'd2: mdv_data_trace_byte = {6'd0, mdv_data_trace_count[9:8]};
                4'd3: mdv_data_trace_byte = mdv_data_trace_count[7:0];
                4'd4: mdv_data_trace_byte = mdv_data_trace[127:120];
                4'd5: mdv_data_trace_byte = mdv_data_trace[119:112];
                4'd6: mdv_data_trace_byte = mdv_data_trace[111:104];
                4'd7: mdv_data_trace_byte = mdv_data_trace[103:96];
                4'd8: mdv_data_trace_byte = mdv_data_trace[95:88];
                4'd9: mdv_data_trace_byte = mdv_data_trace[87:80];
                4'd10: mdv_data_trace_byte = mdv_data_trace[79:72];
                4'd11: mdv_data_trace_byte = mdv_data_trace[71:64];
                4'd12: mdv_data_trace_byte = mdv_data_trace[63:56];
                4'd13: mdv_data_trace_byte = mdv_data_trace[55:48];
                4'd14: mdv_data_trace_byte = mdv_data_trace[47:40];
                4'd15: mdv_data_trace_byte = mdv_data_trace[39:32];
                default: mdv_data_trace_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] debug_state_byte;
        input [3:0] index;
        begin
            case (index)
                4'd0: debug_state_byte = debug_captured_value[31:24];
                4'd1: debug_state_byte = debug_captured_value[23:16];
                4'd2: debug_state_byte = debug_captured_value[15:8];
                4'd3: debug_state_byte = debug_captured_value[7:0];
                4'd4: debug_state_byte = debug_captured_pc[31:24];
                4'd5: debug_state_byte = debug_captured_pc[23:16];
                4'd6: debug_state_byte = debug_captured_pc[15:8];
                4'd7: debug_state_byte = debug_captured_pc[7:0];
                4'd8: debug_state_byte = debug_captured_sr[15:8];
                4'd9: debug_state_byte = debug_captured_sr[7:0];
                4'd10: debug_state_byte = debug_captured_ir[15:8];
                4'd11: debug_state_byte = debug_captured_ir[7:0];
                default: debug_state_byte = 8'h00;
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
            transfer_write <= 1'b1;
            result_index <= 4'd0;
            exec_fetch_seen <= 1'b0;
            exec_video_write_seen <= 1'b0;
            hold_pending <= 1'b0;
            debug_capture_count <= 6'd0;
            debug_captured_value <= 32'd0;
            debug_captured_pc <= 32'd0;
            debug_captured_sr <= 16'd0;
            debug_captured_ir <= 16'd0;
            mem_req <= 1'b0;
            mem_addr <= 22'd0;
            mem_ds <= 2'b00;
            mem_wdata <= 16'd0;
            cpu_hold <= 1'b0;
            cpu_debug_reg_select <= 5'd0;
            cpu_debug_bit_select <= 5'd0;
            boot_vectors_active <= 1'b0;
            boot_ssp <= 32'h0003fff0;
            boot_pc <= 32'h00030000;
            restart_pulse <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                payload[i] <= 8'd0;
                read_payload[i] <= 8'd0;
            end
        end else begin
            restart_pulse <= 1'b0;

            // Stop only between external bus cycles. Gating fx68k's phase
            // enables here preserves its complete microarchitectural state
            // without abandoning a half-completed SDRAM transaction.
            if (hold_pending && cpu_as_n) begin
                cpu_hold <= 1'b1;
                hold_pending <= 1'b0;
            end

            // A one-bit scan port avoids a 17 x 32-bit combinational mux in
            // the crowded FPGA fabric. The CPU is frozen, so collecting one
            // architectural register over 32 system clocks is coherent.
            if (debug_capture_count != 6'd0) begin
                debug_captured_value[cpu_debug_bit_select] <=
                    cpu_debug_reg_bit;
                debug_capture_count <= debug_capture_count - 6'd1;
                if (cpu_debug_bit_select != 5'd0)
                    cpu_debug_bit_select <= cpu_debug_bit_select - 5'd1;
            end

            if (boot_vectors_active && !cpu_as_n && !cpu_dtack_n) begin
                if (cpu_rw && cpu_fc[1] &&
                    (cpu_addr >= 24'h030000) &&
                    (cpu_addr <= 24'h03ffff))
                    exec_fetch_seen <= 1'b1;
                if (!cpu_rw && (cpu_addr >= 24'h020000) &&
                    (cpu_addr <= 24'h027fff))
                    exec_video_write_seen <= 1'b1;
            end

            case (write_state)
                WR_REQ: begin
                    mem_req <= 1'b1;
                    // Host reads use logical QL addresses. RAM is stored at
                    // its native address, while the dynamic 64 KiB system ROM
                    // lives in the reserved final SDRAM block.
                    mem_addr <= (!transfer_write &&
                                 (write_addr <= 24'h00ffff)) ?
                                (ROM_SDRAM_BASE +
                                 {7'd0, write_addr[15:1]}) :
                                write_addr[22:1];
                    if (!transfer_write) begin
                        mem_ds <= 2'b00;
                        mem_wdata <= 16'h0000;
                    end else if (!write_addr[0]) begin
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
                    if ((transfer_write && mem_write_done) ||
                        (!transfer_write && mem_data_valid)) begin
                        if (!transfer_write)
                            read_payload[write_index] <= write_addr[0] ?
                                                         mem_rdata[7:0] :
                                                         mem_rdata[15:8];
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
                            hold_pending <= !cpu_as_n;
                            if (cpu_as_n)
                                cpu_hold <= 1'b1;
                            boot_vectors_active <= 1'b0;
                            exec_fetch_seen <= 1'b0;
                            exec_video_write_seen <= 1'b0;
                            protocol_error <= 1'b0;
                        end
                        CMD_RESUME: begin
                            // Continue the exact frozen fx68k state. Unlike
                            // EXEC and QDOS this does not pulse reset or alter
                            // the boot vectors.
                            cpu_hold <= 1'b0;
                            hold_pending <= 1'b0;
                            protocol_error <= 1'b0;
                        end
                        CMD_QDOS: begin
                            cpu_hold <= 1'b0;
                            hold_pending <= 1'b0;
                            boot_vectors_active <= 1'b0;
                            exec_fetch_seen <= 1'b0;
                            exec_video_write_seen <= 1'b0;
                            protocol_error <= 1'b0;
                            restart_pulse <= 1'b1;
                        end
                        CMD_STATUS: begin
                            status_index <= 4'd1;
                            data_out <= status_byte(4'd0);
                        end
                        CMD_QLSD: begin
                            status_index <= 4'd1;
                            data_out <= qlsd_diag_byte(4'd0);
                        end
                        CMD_CPU: begin
                            status_index <= 4'd1;
                            data_out <= cpu_diag_byte(4'd0);
                        end
                        CMD_MDV: begin
                            status_index <= 4'd1;
                            data_out <= mdv_diag_byte(4'd0);
                        end
                        CMD_MDV_TRACE: begin
                            status_index <= 4'd1;
                            data_out <= mdv_trace_byte(4'd0);
                        end
                        CMD_MDV_DATA_TRACE: begin
                            status_index <= 4'd1;
                            data_out <= mdv_data_trace_byte(4'd0);
                        end
                        CMD_DEBUG: begin
                            data_out <= 8'h44; // D
                            if (!cpu_hold)
                                protocol_error <= 1'b1;
                        end
                        CMD_DEBUG_RESULT: begin
                            data_out <= 8'h44; // D
                            if (!cpu_hold || (debug_capture_count != 6'd0))
                                protocol_error <= 1'b1;
                        end
                        CMD_DEBUG_INFO: begin
                            // An explicit signature lets the host reject old
                            // bitstreams before attempting logical ROM reads.
                            status_index <= 4'd0;
                            data_out <= 8'h44; // D
                        end
                        CMD_RESULT: begin
                            result_index <= 4'd1;
                            data_out <= read_payload[0];
                        end
                        default: begin end
                    endcase
                end else begin
                    field_index <= field_index + 4'd1;

                    if (command == CMD_STATUS) begin
                        data_out <= status_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_QLSD) begin
                        data_out <= qlsd_diag_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_CPU) begin
                        data_out <= cpu_diag_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_MDV) begin
                        data_out <= mdv_diag_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_MDV_TRACE) begin
                        data_out <= mdv_trace_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_MDV_DATA_TRACE) begin
                        data_out <= mdv_data_trace_byte(status_index);
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_DEBUG) begin
                        if (field_index == 4'd0) begin
                            cpu_debug_reg_select <= data_in[4:0];
                            cpu_debug_bit_select <= 5'd31;
                            debug_capture_count <= 6'd32;
                            debug_captured_pc <= cpu_debug_pc;
                            debug_captured_sr <= cpu_debug_sr;
                            debug_captured_ir <= cpu_debug_ir;
                        end
                    end else if (command == CMD_DEBUG_RESULT) begin
                        if (field_index == 4'd0)
                            data_out <= 8'h52; // R
                        else begin
                            data_out <= debug_state_byte(field_index - 4'd1);
                        end
                    end else if (command == CMD_DEBUG_INFO) begin
                        case (status_index)
                            4'd0: data_out <= 8'h42; // B
                            4'd1: data_out <= 8'h32; // protocol 2
                            // coherent reads, logical ROM, fx68k registers
                            4'd2: data_out <= 8'h07;
                            4'd3: data_out <= 8'h08; // max read length
                            default: data_out <= 8'h00;
                        endcase
                        if (status_index != 4'd15)
                            status_index <= status_index + 4'd1;
                    end else if (command == CMD_RESULT) begin
                        if (result_index < 4'd8) begin
                            data_out <= read_payload[result_index];
                            result_index <= result_index + 4'd1;
                        end else begin
                            data_out <= 8'h00;
                        end
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
                                        !ram_address_valid ||
                                        ({1'b0, packet_addr} + packet_length >
                                         25'h0040000)) begin
                                        protocol_error <= 1'b1;
                                    end else begin
                                        transfer_write <= 1'b1;
                                        write_addr <= packet_addr;
                                        write_index <= 4'd0;
                                        write_state <= WR_REQ;
                                    end
                                end
                            end
                        endcase
                    end else if (command == CMD_READ) begin
                        case (field_index)
                            4'd0: packet_addr[23:16] <= data_in;
                            4'd1: packet_addr[15:8] <= data_in;
                            4'd2: packet_addr[7:0] <= data_in;
                            4'd3: begin
                                packet_length <= data_in[3:0];
                                if (busy || !sdram_ready ||
                                    !read_address_valid || (data_in == 8'd0) ||
                                    (data_in > 8'd8) ||
                                    (rom_address_valid &&
                                     ({1'b0, packet_addr} + data_in >
                                      25'h0010000)) ||
                                    (ram_address_valid &&
                                     ({1'b0, packet_addr} + data_in >
                                      25'h0040000))) begin
                                    protocol_error <= 1'b1;
                                end else begin
                                    protocol_error <= 1'b0;
                                    transfer_write <= 1'b0;
                                    write_addr <= packet_addr;
                                    write_index <= 4'd0;
                                    write_state <= WR_REQ;
                                end
                            end
                            default: begin end
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
                                    !((({exec_pc[31:8], data_in} <=
                                        32'h0000ffff)) ||
                                      (({exec_pc[31:8], data_in} >=
                                        32'h00020000) &&
                                       ({exec_pc[31:8], data_in} <=
                                        32'h0003ffff))) ||
                                    exec_ssp[0] || data_in[0]) begin
                                    protocol_error <= 1'b1;
                                end else begin
                                    boot_ssp <= exec_ssp;
                                    boot_pc <= {exec_pc[31:8], data_in};
                                    boot_vectors_active <= 1'b1;
                                    exec_fetch_seen <= 1'b0;
                                    exec_video_write_seen <= 1'b0;
                                    cpu_hold <= 1'b0;
                                    hold_pending <= 1'b0;
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
