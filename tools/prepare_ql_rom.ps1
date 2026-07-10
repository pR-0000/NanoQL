param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath = (Join-Path $PSScriptRoot "..\src\rom\ql_system_rom.hex")
)

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$bytes = [System.IO.File]::ReadAllBytes($resolvedInput)

if (($bytes.Length -ne 49152) -and ($bytes.Length -ne 65536)) {
    throw "Expected a 48 KiB (49152-byte) or 64 KiB (65536-byte) QL ROM dump; got $($bytes.Length) bytes."
}

$padded = New-Object byte[] 65536
for ($index = 0; $index -lt $padded.Length; $index++) {
    $padded[$index] = 0xff
}
[Array]::Copy($bytes, $padded, $bytes.Length)

function Read-BigEndianUInt32([byte[]]$Data, [int]$Offset) {
    return ([uint32]$Data[$Offset] -shl 24) -bor
           ([uint32]$Data[$Offset + 1] -shl 16) -bor
           ([uint32]$Data[$Offset + 2] -shl 8) -bor
           [uint32]$Data[$Offset + 3]
}

$initialSp = Read-BigEndianUInt32 $padded 0
$initialPc = Read-BigEndianUInt32 $padded 4

if (($initialSp -band 1) -ne 0) {
    Write-Warning ("Initial SP 0x{0:X8} is odd." -f $initialSp)
}

if ((($initialPc -band 1) -ne 0) -or ($initialPc -ge 0x00010000)) {
    Write-Warning ("Initial PC 0x{0:X8} is unusual for a QL ROM." -f $initialPc)
}

$builder = [System.Text.StringBuilder]::new(163840)
for ($offset = 0; $offset -lt $padded.Length; $offset += 2) {
    [void]$builder.AppendFormat("{0:X2}{1:X2}`n", $padded[$offset], $padded[$offset + 1])
}

$fullOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [System.IO.Path]::GetDirectoryName($fullOutput)
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
[System.IO.File]::WriteAllText($fullOutput, $builder.ToString(), [System.Text.Encoding]::ASCII)

Write-Host ("ROM converted: {0}" -f $fullOutput)
Write-Host ("Input size: {0} bytes; initial SP: 0x{1:X8}; initial PC: 0x{2:X8}" -f $bytes.Length, $initialSp, $initialPc)
