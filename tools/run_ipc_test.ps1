$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$ghdlCommand = Get-Command ghdl -ErrorAction SilentlyContinue

if ($ghdlCommand) {
    $ghdl = $ghdlCommand.Source
} else {
    $packageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $ghdl = Get-ChildItem $packageRoot -Recurse -Filter ghdl.exe `
        -ErrorAction SilentlyContinue | Select-Object -First 1 `
        -ExpandProperty FullName
}

if (-not $ghdl) {
    throw "GHDL was not found. Install it or add ghdl to PATH."
}

$work = Join-Path $env:TEMP "nanoql_ghdl"
New-Item -ItemType Directory -Force -Path $work | Out-Null
Remove-Item (Join-Path $work "work-obj08.cf") -ErrorAction SilentlyContinue

$sources = @(
    "src/ipc/t48/t48_pack-p.vhd",
    "src/ipc/t48/alu_pack-p.vhd",
    "src/ipc/t48/cond_branch_pack-p.vhd",
    "src/ipc/t48/decoder_pack-p.vhd",
    "src/ipc/t48/dmem_ctrl_pack-p.vhd",
    "src/ipc/t48/pmem_ctrl_pack-p.vhd",
    "src/ipc/t48/t48_tb_pack-p.vhd",
    "src/ipc/t48/t48_comp_pack-p.vhd",
    "src/ipc/t48/t48_core_comp_pack-p.vhd",
    "src/ipc/t48/alu.vhd",
    "src/ipc/t48/bus_mux.vhd",
    "src/ipc/t48/clock_ctrl.vhd",
    "src/ipc/t48/cond_branch.vhd",
    "src/ipc/t48/db_bus.vhd",
    "src/ipc/t48/decoder.vhd",
    "src/ipc/t48/dmem_ctrl.vhd",
    "src/ipc/t48/int.vhd",
    "src/ipc/t48/opc_decoder.vhd",
    "src/ipc/t48/opc_table.vhd",
    "src/ipc/t48/p1.vhd",
    "src/ipc/t48/p2.vhd",
    "src/ipc/t48/pmem_ctrl.vhd",
    "src/ipc/t48/psw.vhd",
    "src/ipc/t48/timer.vhd",
    "src/ipc/t48/t48_core.vhd",
    "src/ipc/t48/generic_ram_ena.vhd",
    "src/ipc/t48/t49_rom-e.vhd",
    "sim/t49_rom_sim.vhd",
    "src/ipc/t48/t8049_notri.vhd",
    "sim/tb_ql_ipc.vhd"
)

foreach ($source in $sources) {
    & $ghdl -a --std=08 --workdir=$work (Join-Path $projectRoot $source)
    if ($LASTEXITCODE -ne 0) {
        throw "GHDL analysis failed for $source."
    }
}

Push-Location $projectRoot
try {
    & $ghdl -r --std=08 --workdir=$work tb_ql_ipc `
        --assert-level=error --ieee-asserts=disable-at-0
    if ($LASTEXITCODE -ne 0) {
        throw "IPC simulation failed."
    }
} finally {
    Pop-Location
}
