$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$iverilogCommand = Get-Command iverilog -ErrorAction SilentlyContinue
$vvpCommand = Get-Command vvp -ErrorAction SilentlyContinue
$bundledBin = Join-Path $projectRoot "tools\iverilog\bin"
$fallbackBin = "C:\Tools\iverilog\bin"

if ($iverilogCommand -and $vvpCommand) {
    $iverilog = $iverilogCommand.Source
    $vvp = $vvpCommand.Source
} elseif (Test-Path -LiteralPath (Join-Path $bundledBin "iverilog.exe")) {
    $iverilog = Join-Path $bundledBin "iverilog.exe"
    $vvp = Join-Path $bundledBin "vvp.exe"
} elseif (Test-Path -LiteralPath (Join-Path $fallbackBin "iverilog.exe")) {
    $iverilog = Join-Path $fallbackBin "iverilog.exe"
    $vvp = Join-Path $fallbackBin "vvp.exe"
} else {
    throw "Icarus Verilog was not found. Install it or add iverilog and vvp to PATH."
}

$logicalOutput = Join-Path $env:TEMP "nanoql_bus_memory.vvp"
$physicalOutput = Join-Path $env:TEMP "nanoql_sdram_controller.vvp"
$zx8302Output = Join-Path $env:TEMP "nanoql_zx8302.vvp"
$zx8302BusOutput = Join-Path $env:TEMP "nanoql_zx8302_bus.vvp"
$romLoaderOutput = Join-Path $env:TEMP "nanoql_sd_rom_loader.vvp"
$cpuAddressOutput = Join-Path $env:TEMP "nanoql_cpu_address.vvp"
$hostLinkOutput = Join-Path $env:TEMP "nanoql_host_link.vvp"
$hdmiAudioOutput = Join-Path $env:TEMP "nanoql_hdmi_audio.vvp"
$sdramRouterOutput = Join-Path $env:TEMP "nanoql_sdram_router.vvp"
$memoryMapOutput = Join-Path $env:TEMP "nanoql_memory_map_ram.vvp"
$cpuPhaseOutput = Join-Path $env:TEMP "nanoql_cpu_phase.vvp"
$qlromextOutput = Join-Path $env:TEMP "nanoql_qlromext.vvp"
$qlsdBufferOutput = Join-Path $env:TEMP "nanoql_qlsd_buffer.vvp"
$microdriveOutput = Join-Path $env:TEMP "nanoql_microdrive_stream.vvp"
$sdArbiterOutput = Join-Path $env:TEMP "nanoql_sd_request_arbiter.vvp"

& $iverilog -g2012 -s tb_ql_sd_request_arbiter -o $sdArbiterOutput `
    (Join-Path $projectRoot "sim\tb_ql_sd_request_arbiter.sv") `
    (Join-Path $projectRoot "src\ql_sd_request_arbiter.sv")

if ($LASTEXITCODE -ne 0) {
    throw "SD request arbiter simulation compilation failed."
}

& $vvp $sdArbiterOutput
if ($LASTEXITCODE -ne 0) {
    throw "SD request arbiter simulation failed."
}

& $iverilog -g2012 -s tb_ql_microdrive_stream -o $microdriveOutput `
    (Join-Path $projectRoot "sim\tb_ql_microdrive_stream.sv") `
    (Join-Path $projectRoot "src\ql_microdrive_stream.sv")

if ($LASTEXITCODE -ne 0) {
    throw "Microdrive stream simulation compilation failed."
}

& $vvp $microdriveOutput
if ($LASTEXITCODE -ne 0) {
    throw "Microdrive stream simulation failed."
}

& $iverilog -g2012 -s tb_ql_sd_card_buffer -o $qlsdBufferOutput `
    (Join-Path $projectRoot "sim\tb_ql_sd_card_buffer.sv") `
    (Join-Path $projectRoot "src\companion\vendor\ql_sd_card.sv")

if ($LASTEXITCODE -ne 0) {
    throw "QL-SD sector-buffer simulation compilation failed."
}

& $vvp $qlsdBufferOutput
if ($LASTEXITCODE -ne 0) {
    throw "QL-SD sector-buffer simulation failed."
}

& $iverilog -g2012 -s tb_ql_sd_qlromext -o $qlromextOutput `
    (Join-Path $projectRoot "sim\tb_ql_sd_qlromext.sv") `
    (Join-Path $projectRoot "src\ql_sd_qlromext.sv")

if ($LASTEXITCODE -ne 0) {
    throw "QLROMEXT simulation compilation failed."
}

& $vvp $qlromextOutput
if ($LASTEXITCODE -ne 0) {
    throw "QLROMEXT simulation failed."
}

& $iverilog -g2012 -s tb_ql_cpu_phase -o $cpuPhaseOutput `
    (Join-Path $projectRoot "sim\tb_ql_cpu_phase.sv") `
    (Join-Path $projectRoot "src\ql_cpu_phase.sv")

if ($LASTEXITCODE -ne 0) {
    throw "CPU phase simulation compilation failed."
}

& $vvp $cpuPhaseOutput
if ($LASTEXITCODE -ne 0) {
    throw "CPU phase simulation failed."
}

& $iverilog -g2012 -s tb_ql_memory_map_ram -o $memoryMapOutput `
    (Join-Path $projectRoot "sim\tb_ql_memory_map_ram.sv") `
    (Join-Path $projectRoot "src\ql_memory_map.sv")

if ($LASTEXITCODE -ne 0) {
    throw "RAM memory-map simulation compilation failed."
}

& $vvp $memoryMapOutput
if ($LASTEXITCODE -ne 0) {
    throw "RAM memory-map simulation failed."
}

& $iverilog -g2012 -s tb_ql_sdram_router -o $sdramRouterOutput `
    (Join-Path $projectRoot "sim\tb_ql_sdram_router.sv") `
    (Join-Path $projectRoot "src\ql_sdram_router.sv")

if ($LASTEXITCODE -ne 0) {
    throw "SDRAM router simulation compilation failed."
}

& $vvp $sdramRouterOutput
if ($LASTEXITCODE -ne 0) {
    throw "SDRAM router simulation failed."
}

& $iverilog -g2012 -s tb_ql_hdmi_audio -o $hdmiAudioOutput `
    (Join-Path $projectRoot "sim\tb_ql_hdmi_audio.sv") `
    (Join-Path $projectRoot "src\ql_hdmi_audio.sv")

if ($LASTEXITCODE -ne 0) {
    throw "HDMI audio simulation compilation failed."
}

& $vvp $hdmiAudioOutput
if ($LASTEXITCODE -ne 0) {
    throw "HDMI audio simulation failed."
}

& $iverilog -g2012 -s tb_ql_cpu_address -o $cpuAddressOutput `
    (Join-Path $projectRoot "sim\tb_ql_cpu_address.sv") `
    (Join-Path $projectRoot "src\ql_cpu_address.sv")

if ($LASTEXITCODE -ne 0) {
    throw "CPU address-map simulation compilation failed."
}

& $vvp $cpuAddressOutput
if ($LASTEXITCODE -ne 0) {
    throw "CPU address-map simulation failed."
}

& $iverilog -g2012 -s tb_ql_host_link -o $hostLinkOutput `
    (Join-Path $projectRoot "sim\tb_ql_host_link.sv") `
    (Join-Path $projectRoot "src\companion\ql_host_link.sv")

if ($LASTEXITCODE -ne 0) {
    throw "NanoQL Link simulation compilation failed."
}

& $vvp $hostLinkOutput
if ($LASTEXITCODE -ne 0) {
    throw "NanoQL Link simulation failed."
}

& $iverilog -g2012 -s tb_ql_bus_memory -o $logicalOutput `
    (Join-Path $projectRoot "sim\tb_ql_bus_memory.sv") `
    (Join-Path $projectRoot "src\ql_cpu_bus_bridge.sv") `
    (Join-Path $projectRoot "src\ql_sdram_memory.sv") `
    (Join-Path $projectRoot "src\ql_test_pattern.sv")

if ($LASTEXITCODE -ne 0) {
    throw "HDL compilation failed."
}

& $vvp $logicalOutput
if ($LASTEXITCODE -ne 0) {
    throw "Logical memory simulation failed."
}

& $iverilog -g2012 -s tb_ql_sdram_controller -o $physicalOutput `
    (Join-Path $projectRoot "sim\tb_ql_sdram_controller.sv") `
    (Join-Path $projectRoot "src\ql_cpu_bus_bridge.sv") `
    (Join-Path $projectRoot "src\ql_sdram_memory.sv") `
    (Join-Path $projectRoot "src\ql_test_pattern.sv") `
    (Join-Path $projectRoot "src\sdram\sdram.v")

if ($LASTEXITCODE -ne 0) {
    throw "Physical SDRAM model compilation failed."
}

& $vvp $physicalOutput
if ($LASTEXITCODE -ne 0) {
    throw "Physical SDRAM model simulation failed."
}

& $iverilog -g2012 -s tb_ql_zx8302 -o $zx8302Output `
    (Join-Path $projectRoot "sim\tb_ql_zx8302.sv") `
    (Join-Path $projectRoot "src\ql_zx8302.sv")

if ($LASTEXITCODE -ne 0) {
    throw "ZX8302 simulation compilation failed."
}

& $vvp $zx8302Output
if ($LASTEXITCODE -ne 0) {
    throw "ZX8302 simulation failed."
}

& $iverilog -g2012 -s tb_ql_zx8302_bus -o $zx8302BusOutput `
    (Join-Path $projectRoot "sim\tb_ql_zx8302_bus.sv") `
    (Join-Path $projectRoot "src\ql_cpu_bus_bridge.sv") `
    (Join-Path $projectRoot "src\ql_memory_map.sv")

if ($LASTEXITCODE -ne 0) {
    throw "ZX8302 bus simulation compilation failed."
}

& $vvp $zx8302BusOutput
if ($LASTEXITCODE -ne 0) {
    throw "ZX8302 bus simulation failed."
}

& $iverilog -g2012 -s tb_ql_sd_rom_loader -o $romLoaderOutput `
    (Join-Path $projectRoot "sim\tb_ql_sd_rom_loader.sv") `
    (Join-Path $projectRoot "src\companion\ql_sd_rom_loader.sv") `
    (Join-Path $projectRoot "src\companion\ql_rom_sector_buffer.sv")

if ($LASTEXITCODE -ne 0) {
    throw "SD ROM loader simulation compilation failed."
}

& $vvp $romLoaderOutput
if ($LASTEXITCODE -ne 0) {
    throw "SD ROM loader simulation failed."
}
