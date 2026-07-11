param(
    [Parameter(Mandatory = $true)]
    [string]$RomPath,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$rom = Get-Item -LiteralPath $RomPath
$destinationDirectory = Get-Item -LiteralPath $Destination

if (-not $destinationDirectory.PSIsContainer) {
    throw "Destination must be a mounted microSD directory: $Destination"
}

if (($rom.Length -ne 49152) -and ($rom.Length -ne 65536)) {
    throw "QL ROM must contain exactly 49,152 or 65,536 bytes; got $($rom.Length)."
}

$output = Join-Path $destinationDirectory.FullName 'QL.rom'
$config = Join-Path $destinationDirectory.FullName 'nanoql.ini'
Copy-Item -LiteralPath $rom.FullName -Destination $output -Force
[System.IO.File]::WriteAllText(
    $config,
    "drive0 = /sd/QL.rom`n",
    [System.Text.Encoding]::ASCII
)

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $output
Write-Host "Prepared $output"
Write-Host "Prepared $config"
Write-Host "Size: $($rom.Length) bytes"
Write-Host "SHA-256: $($hash.Hash)"
