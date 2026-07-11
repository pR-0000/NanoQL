set ipc_rom_data_file src/ipc/ql_ipc_rom.hex

if {![file exists $ipc_rom_data_file]} {
    error "Missing src/ipc/ql_ipc_rom.hex. Run tools/prepare_ql_ipc_rom.ps1 with your own 8049 IPC firmware dump first."
}

set rom_source src/ql_sd_boot_rom.sv
set zx8302_source src/ql_zx8302_ipc.sv
set include_t48_ipc 1
set output_name NanoQL_sd_rom
source build_common.tcl
