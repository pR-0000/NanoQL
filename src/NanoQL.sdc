create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
create_clock -name clk_sdram -period 20.833 -waveform {0 10.417} [get_ports {O_sdram_clk}] -add
