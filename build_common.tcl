if {![info exists rom_source]} {
    error "rom_source must be set before sourcing build_common.tcl"
}

if {![info exists output_name]} {
    error "output_name must be set before sourcing build_common.tcl"
}

if {![info exists zx8302_source]} {
    error "zx8302_source must be set before sourcing build_common.tcl"
}

if {![info exists hdmi_audio_source]} {
    set hdmi_audio_source src/ql_hdmi_audio.sv
}

set_device GW2AR-LV18QN88C8/I7 -name GW2AR-18C

add_file src/nanoql_top.sv
add_file src/ql_video_test.sv
add_file src/ql_hdmi_window.sv
add_file src/ql_boot_status.sv
add_file src/ql_zx8301.sv
add_file $zx8302_source
add_file src/ql_video_scanout.sv
add_file src/ql_test_pattern.sv
add_file src/ql_sdram_memory.sv
add_file src/ql_sdram_router.sv
add_file src/ql_cpu_bus_bridge.sv
add_file src/ql_timing.sv
add_file src/ql_memory_map.sv
add_file $rom_source
add_file src/ql_cpu_address.sv
add_file src/ql_cpu_phase.sv
add_file src/ql_sd_qlromext.sv
add_file src/ql_sd_request_arbiter.sv
add_file src/ql_microdrive_stream.sv
add_file src/ql_cpu_fx68k.sv
add_file src/ql_cpu_boot_monitor.sv
add_file src/companion/ql_companion_sysctrl.sv
add_file src/companion/ql_companion_hid.sv
add_file src/companion/ql_companion_osd.sv
add_file src/companion/ql_host_link.sv
add_file src/companion/ql_rom_sector_buffer.sv
add_file src/companion/ql_sd_rom_loader.sv
add_file src/companion/vendor/mcu_spi.v
add_file src/companion/vendor/sd_card.v
add_file src/companion/vendor/ql_sd_card.sv
add_file src/companion/vendor/sd_rw.v
add_file src/companion/vendor/sdcmd_ctrl.v
add_file src/companion/vendor/sector_dpram.v
add_file src/companion/nanoql_xml.hex
add_file src/fx68k/fx68k.sv
add_file src/fx68k/fx68kAlu.sv
add_file src/fx68k/uaddrPla.sv
add_file src/sdram/sdram.v
add_file src/nanoql_hdmi.sv
add_file $hdmi_audio_source
add_file src/gowin_rpll/pll_160m.v
add_file src/gowin_rpll/pll_371m.v
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
add_file src/fx68k/microrom.mem
add_file src/fx68k/nanorom.mem

if {[info exists include_t48_ipc]} {
    add_file src/ipc/t48/t48_pack-p.vhd
    add_file src/ipc/t48/alu_pack-p.vhd
    add_file src/ipc/t48/cond_branch_pack-p.vhd
    add_file src/ipc/t48/decoder_pack-p.vhd
    add_file src/ipc/t48/dmem_ctrl_pack-p.vhd
    add_file src/ipc/t48/pmem_ctrl_pack-p.vhd
    add_file src/ipc/t48/t48_tb_pack-p.vhd
    add_file src/ipc/t48/t48_comp_pack-p.vhd
    add_file src/ipc/t48/t48_core_comp_pack-p.vhd
    add_file src/ipc/t48/alu.vhd
    add_file src/ipc/t48/bus_mux.vhd
    add_file src/ipc/t48/clock_ctrl.vhd
    add_file src/ipc/t48/cond_branch.vhd
    add_file src/ipc/t48/db_bus.vhd
    add_file src/ipc/t48/decoder.vhd
    add_file src/ipc/t48/dmem_ctrl.vhd
    add_file src/ipc/t48/int.vhd
    add_file src/ipc/t48/opc_decoder.vhd
    add_file src/ipc/t48/opc_table.vhd
    add_file src/ipc/t48/p1.vhd
    add_file src/ipc/t48/p2.vhd
    add_file src/ipc/t48/pmem_ctrl.vhd
    add_file src/ipc/t48/psw.vhd
    add_file src/ipc/t48/timer.vhd
    add_file src/ipc/t48/t48_core.vhd
    add_file src/ipc/t48/generic_ram_ena.vhd
    add_file src/ipc/t48/t49_rom-e.vhd
    add_file src/ipc/t48/t49_rom-struct-a.vhd
    add_file src/ipc/t48/t8049_notri.vhd
    add_file src/ipc/rom_t49.sv
    add_file src/ipc/ql_ipc_t48.sv
    add_file $ipc_rom_data_file
}

if {[info exists rom_data_file]} {
    add_file $rom_data_file
}

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name $output_name
set_option -verilog_std sysv2017
set_option -loading_rate 25.000
set_option -top_module nanoql_top
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
# Keep the Tang Nano 20K JTAG pins dedicated to the on-board programmer.
# FPGA Companion relies on this path when the BL616 Partner is active.
set_option -use_jtag_as_gpio 0
set_option -bit_compress 1

run all
