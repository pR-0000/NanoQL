module ql_mc6821_pia (
    input  wire       clk,
    input  wire       reset,
    input  wire       write,
    input  wire [1:0] rs,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out,
    input  wire [7:0] port_a_in,
    input  wire [7:0] port_b_in,
    output wire [7:0] port_a_pins,
    output wire [7:0] port_b_pins
);

    reg [7:0] port_a_data;
    reg [7:0] port_b_data;
    reg [7:0] port_a_direction;
    reg [7:0] port_b_direction;
    reg [5:0] control_a;
    reg [5:0] control_b;

    assign port_a_pins = (port_a_data & port_a_direction) |
                         (port_a_in & ~port_a_direction);
    assign port_b_pins = (port_b_data & port_b_direction) |
                         (port_b_in & ~port_b_direction);

    always @(*) begin
        case (rs)
            2'b00: data_out = control_a[2] ? port_a_pins : port_a_direction;
            2'b01: data_out = {2'b00, control_a};
            2'b10: data_out = control_b[2] ? port_b_pins : port_b_direction;
            default: data_out = {2'b00, control_b};
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            port_a_data <= 8'd0;
            port_b_data <= 8'd0;
            port_a_direction <= 8'd0;
            port_b_direction <= 8'd0;
            control_a <= 6'd0;
            control_b <= 6'd0;
        end else if (write) begin
            case (rs)
                2'b00: begin
                    if (control_a[2])
                        port_a_data <= data_in;
                    else
                        port_a_direction <= data_in;
                end
                2'b01: control_a <= data_in[5:0];
                2'b10: begin
                    if (control_b[2])
                        port_b_data <= data_in;
                    else
                        port_b_direction <= data_in;
                end
                2'b11: control_b <= data_in[5:0];
            endcase
        end
    end

endmodule
