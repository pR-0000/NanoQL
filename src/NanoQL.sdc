create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
create_clock -name clk_sdram -period 31.447 -waveform {0 15.724} [get_ports {O_sdram_clk}] -add
