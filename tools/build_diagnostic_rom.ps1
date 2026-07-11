param(
    [Parameter(Mandatory = $true)]
    [string]$VasmPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\rom\ql_diagnostic.s'
$output = Join-Path $root 'src\rom\ql_diagnostic_rom.vh'
$binary = Join-Path $env:TEMP 'nanoql_diagnostic.bin'

& $VasmPath -m68000 -Fbin -quiet -o $binary $source
if ($LASTEXITCODE -ne 0) {
    throw "vasm failed with exit code $LASTEXITCODE"
}

$bytes = [System.IO.File]::ReadAllBytes($binary)
if (($bytes.Length -band 1) -ne 0) {
    throw 'The diagnostic ROM has an odd byte count.'
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('            // Generated from src/rom/ql_diagnostic.s.')
for ($offset = 0; $offset -lt $bytes.Length; $offset += 2) {
    $word = ($bytes[$offset] -shl 8) -bor $bytes[$offset + 1]
    if ($word -ne 0xffff) {
        $lines.Add(('            15''h{0:x4}: data = 16''h{1:x4};' -f ($offset / 2), $word))
    }
}

[System.IO.File]::WriteAllLines($output, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $output from $source"
