param(
    [ValidateSet('both', '3921', '3923')]
    [string]$Revision = 'both',
    [switch]$Launch,
    [switch]$ForceDownload
)

$ErrorActionPreference = 'Stop'
$arguments = @(
    (Join-Path $PSScriptRoot 'prepare_bl616_firmware.py'),
    '--revision',
    $Revision
)
if ($Launch) {
    $arguments += '--launch'
}
if ($ForceDownload) {
    $arguments += '--force-download'
}

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "BL616 package preparation failed with exit code $LASTEXITCODE."
}
