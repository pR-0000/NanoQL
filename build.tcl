set_device GW2AR-LV18QN88C8/I7 -name GW2AR-18C

add_file src/nanoql_top.sv
add_file src/ql_video_test.sv
add_file src/ql_hdmi_window.sv
add_file src/ql_zx8301_lite.sv
add_file src/ql_video_scanout.sv
add_file src/ql_native_timing_probe.sv
add_file src/ql_test_pattern.sv
add_file src/ql_sdram_memory.sv
add_file src/ql_sdram_test_writer.sv
add_file src/sdram/sdram.v
add_file src/nanoql_hdmi.sv
add_file src/gowin_rpll/pll_160m.v
add_file src/gowin_clkdiv/gowin_clkdiv.v
add_file src/hdmi/audio_clock_regeneration_packet.sv
add_file src/hdmi/audio_info_frame.sv
add_file src/hdmi/audio_sample_packet.sv
add_file src/hdmi/auxiliary_video_information_info_frame.sv
add_file src/hdmi/hdmi.sv
add_file src/hdmi/packet_assembler.sv
add_file src/hdmi/packet_picker.sv
add_file src/hdmi/serializer.sv
add_file src/hdmi/source_product_description_info_frame.sv
add_file src/hdmi/tmds_channel.sv
add_file src/NanoQL.cst
add_file src/NanoQL.sdc

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name NanoQL
set_option -verilog_std sysv2017
set_option -loading_rate 25.000
set_option -top_module nanoql_top
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -bit_compress 1

run all
