param(
    [ValidateSet('both', '3921', '3923')]
    [string]$Revision = 'both',
    [switch]$Launch,
    [switch]$ForceDownload
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$releaseTag = 'v1.4.22'
$releaseBase = "https://github.com/MiSTle-Dev/FPGA-Companion/releases/download/$releaseTag"
$flashCubeUrl = 'https://github.com/MiSTle-Dev/.github/wiki/.assets/bouffalo_flash_cube-1.1.zip'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cacheRoot = Join-Path $repositoryRoot 'private/bl616'
$packageRoot = Join-Path $cacheRoot 'flash-package'
$toolRoot = Join-Path $cacheRoot 'flashcube'
$toolArchive = Join-Path $cacheRoot 'bouffalo_flash_cube-1.1.zip'

$downloads = @(
    @{
        Name = 'bl616_bootloader_0x20000_nano20k_signed.bin'
        Url = "$releaseBase/bl616_bootloader_0x20000_nano20k_signed.bin"
        Sha256 = '1B5D0ED698A3F2BF0B9D4F72D242868DA993E737BBEA0C8288267B69B73FBC12'
    },
    @{
        Name = 'bl616_fpga_partner_nano20k.bin'
        Url = "$releaseBase/bl616_fpga_partner_nano20k.bin"
        Sha256 = 'BC5B1F733A13562C898FF66B540038C116C3D77CA202D0AFEBD1E7AF1C3B3203'
    },
    @{
        Name = 'fpga_companion_nano20k.bin'
        Url = "$releaseBase/fpga_companion_nano20k.bin"
        Sha256 = 'D8DEBB481F611C599AAE2877E1B92A3611250F23D0A0ACF36BB692A55FA89741'
    },
    @{
        Name = 'bl616_fpga_partner_nano20k_v3923.bin'
        Url = "$releaseBase/bl616_fpga_partner_nano20k_v3923.bin"
        Sha256 = 'BC5B1F733A13562C898FF66B540038C116C3D77CA202D0AFEBD1E7AF1C3B3203'
    },
    @{
        Name = 'fpga_companion_nano20k_v3923.bin'
        Url = "$releaseBase/fpga_companion_nano20k_v3923.bin"
        Sha256 = '07AD01E6260BA6387F2215EDB7E20D630D50A32A03436CEF45A61A1DD1AB308A'
    }
)

function Get-VerifiedDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if ((Test-Path -LiteralPath $Destination) -and -not $ForceDownload) {
        $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
        if ($currentHash -eq $ExpectedSha256) {
            Write-Host "Verified cached file: $Destination"
            return
        }
        Write-Warning "Cached file has the wrong hash and will be downloaded again: $Destination"
    }

    $temporaryPath = "$Destination.download"
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    Write-Host "Downloading $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temporaryPath

    $downloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryPath).Hash
    if ($downloadHash -ne $ExpectedSha256) {
        Remove-Item -LiteralPath $temporaryPath -Force
        throw "SHA-256 mismatch for $Url. Expected $ExpectedSha256, got $downloadHash."
    }

    Move-Item -LiteralPath $temporaryPath -Destination $Destination -Force
    Write-Host "Verified SHA-256: $downloadHash"
}

New-Item -ItemType Directory -Force -Path $cacheRoot, $packageRoot | Out-Null

foreach ($download in $downloads) {
    Get-VerifiedDownload `
        -Url $download.Url `
        -Destination (Join-Path $packageRoot $download.Name) `
        -ExpectedSha256 $download.Sha256
}

@(
    'flash_nano20k.ini',
    'flash_nano20k_unconditional.ini',
    'flash_nano20k_companion_only.ini',
    '1_NORMAL_partner_auto.ini',
    '2_TEST_companion_only.ini',
    '1_NORMAL_3921_partner_auto.ini',
    '2_TEST_3921_companion_only.ini',
    '1_NORMAL_3923_partner_auto.ini',
    '2_TEST_3923_companion_only.ini'
) | ForEach-Object {
    Remove-Item -LiteralPath (Join-Path $packageRoot $_) -Force -ErrorAction SilentlyContinue
}

$revisions = if ($Revision -eq 'both') { @('3921', '3923') } else { @($Revision) }
foreach ($boardRevision in $revisions) {
    $normalSource = Join-Path $repositoryRoot "firmware/bl616/flash_nano20k_$boardRevision.ini"
    $normalDestination = Join-Path $packageRoot "1_NORMAL_${boardRevision}_partner_auto.ini"
    $testSource = Join-Path $repositoryRoot "firmware/bl616/flash_nano20k_${boardRevision}_companion_only.ini"
    $testDestination = Join-Path $packageRoot "2_TEST_${boardRevision}_companion_only.ini"
    Copy-Item -LiteralPath $normalSource -Destination $normalDestination -Force
    Copy-Item -LiteralPath $testSource -Destination $testDestination -Force
}

Get-VerifiedDownload `
    -Url $flashCubeUrl `
    -Destination $toolArchive `
    -ExpectedSha256 '2FD7EA7FBE4499CC1897145FDDE74E5551BDDCD27C68115BF6A065FDBD92B181'

$flashCubeExecutable = Get-ChildItem -Path $toolRoot -Recurse -Filter 'BLFlashCube.exe' `
    -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $flashCubeExecutable) {
    New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
    Write-Host "Extracting BouffaloLabFlashCube to $toolRoot"
    Expand-Archive -LiteralPath $toolArchive -DestinationPath $toolRoot -Force
    $flashCubeExecutable = Get-ChildItem -Path $toolRoot -Recurse -Filter 'BLFlashCube.exe' |
        Select-Object -First 1
}

if (-not $flashCubeExecutable) {
    throw 'BLFlashCube.exe was not found after extraction.'
}

Write-Host ''
Write-Host 'BL616 package ready.' -ForegroundColor Green
Write-Host "Release: $releaseTag"
Write-Host "FlashCube: $($flashCubeExecutable.FullName)"
foreach ($boardRevision in $revisions) {
    $normalPath = Join-Path $packageRoot "1_NORMAL_${boardRevision}_partner_auto.ini"
    $testPath = Join-Path $packageRoot "2_TEST_${boardRevision}_companion_only.ini"
    Write-Host "Revision $boardRevision normal: $normalPath"
    Write-Host "Revision $boardRevision test:   $testPath"
}
Write-Host ''
Write-Host 'NORMAL keeps the Gowin programmer while USB data is connected.'
Write-Host 'To run Companion with NORMAL, boot the FPGA from its Flash and power the'
Write-Host 'board from USB without a data host. TEST disables the programmer and runs'
Write-Host 'Companion even while a PC is connected.'
Write-Host ''
Write-Host 'Then hold UPDATE, connect USB-C, release UPDATE, refresh the COM ports,'
Write-Host 'select the new port, and click Download.'

if ($Launch) {
    Start-Process -FilePath $flashCubeExecutable.FullName -WorkingDirectory $packageRoot
}
