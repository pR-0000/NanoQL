//Copyright (C)2014-2021 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9C
//Created Time: Fri Nov 12 13:46:33 2021

module Gowin_CLKDIV #(
    // Twice the requested divider: 7 selects 3.5 and 10 selects 5.
    parameter integer DIVIDE_X2 = 10
) (clkout, hclkin, resetn);

output clkout;
input hclkin;
input resetn;

wire gw_gnd;

assign gw_gnd = 1'b0;

generate
    if (DIVIDE_X2 == 7) begin : generate_div3p5
        CLKDIV clkdiv_inst (
            .CLKOUT(clkout),
            .HCLKIN(hclkin),
            .RESETN(resetn),
            .CALIB(gw_gnd)
        );
        defparam clkdiv_inst.DIV_MODE = "3.5";
        defparam clkdiv_inst.GSREN = "false";
    end else begin : generate_div5
        CLKDIV clkdiv_inst (
            .CLKOUT(clkout),
            .HCLKIN(hclkin),
            .RESETN(resetn),
            .CALIB(gw_gnd)
        );
        defparam clkdiv_inst.DIV_MODE = "5";
        defparam clkdiv_inst.GSREN = "false";
    end
endgenerate

endmodule //Gowin_CLKDIV
