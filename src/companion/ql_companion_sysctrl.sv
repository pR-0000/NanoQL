module ql_companion_sysctrl(
    input  wire       clk,
    input  wire       reset,
    input  wire       data_strobe,
    input  wire       data_start,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out,
    input  wire       sd_irq,
    output reg        sd_iack,
    output wire       int_out_n,
    input  wire [1:0] buttons,
    output reg  [1:0] system_reset,
    output reg  [1:0] video_aspect,
    output reg  [1:0] ram_config,
    output reg  [1:0] cpu_speed,
    output reg        host_keyboard_azerty,
    output reg        rom_keyboard_french,
    output reg        status_seen,
    output reg        config_seen
);

    reg [7:0] command;
    reg [7:0] config_id;
    reg [3:0] state;
    reg coldboot;
    reg [10:0] config_addr;
    reg [7:0] config_data;
    reg [7:0] config_rom [0:2047];

    initial $readmemh("src/companion/nanoql_xml.hex", config_rom);

    assign int_out_n = (coldboot || sd_irq) ? 1'b0 : 1'b1;

    always @(posedge clk) begin
        config_data <= config_rom[config_addr];

        if (reset) begin
            command <= 8'hff;
            config_id <= 8'd0;
            state <= 4'd0;
            coldboot <= 1'b1;
            config_addr <= 11'd0;
            data_out <= 8'd0;
            sd_iack <= 1'b0;
            system_reset <= 2'd1;
            video_aspect <= 2'd2;
            ram_config <= 2'd0;
            cpu_speed <= 2'd0;
            host_keyboard_azerty <= 1'b0;
            rom_keyboard_french <= 1'b0;
            status_seen <= 1'b0;
            config_seen <= 1'b0;
        end else begin
            sd_iack <= 1'b0;

            if (data_strobe) begin
                if (data_start) begin
                    command <= data_in;
                    state <= 4'd0;
                    config_addr <= 11'd0;
                    data_out <= 8'd0;
                    if (data_in == 8'd0)
                        status_seen <= 1'b1;
                    if (data_in == 8'd8)
                        config_seen <= 1'b1;
                end else begin
                    if (state != 4'd15)
                        state <= state + 4'd1;

                    case (command)
                        8'd0: begin
                            if (state == 4'd0) data_out <= 8'h5c;
                            if (state == 4'd1) data_out <= 8'h42;
                            // Core ID zero selects the current generic protocol.
                            if (state == 4'd2) data_out <= 8'h00;
                        end

                        8'd3: begin
                            data_out <= {6'b000000, buttons};
                        end

                        8'd4: begin
                            if (state == 4'd0)
                                config_id <= data_in;
                            else if (state == 4'd1) begin
                                if (config_id == "R")
                                    system_reset <= data_in[1:0];
                                else if (config_id == "A")
                                    video_aspect <= data_in[1:0];
                                else if (config_id == "M")
                                    ram_config <= data_in[1:0];
                                else if (config_id == "C")
                                    cpu_speed <= data_in[1:0];
                                else if (config_id == "H")
                                    host_keyboard_azerty <= data_in[0];
                                else if (config_id == "K")
                                    rom_keyboard_french <= data_in[0];
                            end
                        end

                        8'd5: begin
                            if (state == 4'd0) begin
                                if (data_in[3])
                                    sd_iack <= 1'b1;
                                if (data_in[0])
                                    coldboot <= 1'b0;
                            end
                            data_out <= {4'b0000, sd_irq, 2'b00, coldboot};
                        end

                        8'd6: begin
                            data_out <= {4'b0000, sd_irq, 2'b00, coldboot};
                            if (state == 4'd0)
                                coldboot <= 1'b0;
                        end

                        8'd8: begin
                            data_out <= config_data;
                            config_addr <= config_addr + 11'd1;
                        end

                        default: data_out <= 8'd0;
                    endcase
                end
            end
        end
    end

endmodule
