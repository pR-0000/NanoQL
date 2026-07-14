set ipc_rom_data_file src/ipc/ql_ipc_rom.hex

if {![file exists $ipc_rom_data_file]} {
    error "Missing src/ipc/ql_ipc_rom.hex. Use tools/nanoql_setup.py to convert MiSTer's standard ipc8049.hex first."
}

set rom_source src/ql_sd_boot_rom.sv
set zx8302_source src/ql_zx8302.sv
set include_t48_ipc 1
set hdmi_audio_source src/ql_hdmi_audio_test.sv
set output_name NanoQL_audio_test
source build_common.tcl
