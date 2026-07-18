param(
    [Parameter(Mandatory = $true)]
    [string]$RomPath,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$MdvFolder,

    [string]$MdvName = 'NANOQL'
)

$ErrorActionPreference = 'Stop'
$arguments = @(
    (Join-Path $PSScriptRoot 'prepare_sd_card.py'),
    $RomPath,
    $Destination
)
if ($MdvFolder) {
    $arguments += @('--mdv-folder', $MdvFolder, '--mdv-name', $MdvName)
}

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "microSD preparation failed with exit code $LASTEXITCODE."
}
