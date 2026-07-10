param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath = (Join-Path $PSScriptRoot "..\src\ipc\ql_ipc_rom.hex")
)

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$rom = New-Object byte[] 2048
for ($index = 0; $index -lt $rom.Length; $index++) {
    $rom[$index] = 0xff
}
$written = New-Object bool[] 2048
$upperAddress = 0
$eofSeen = $false

foreach ($rawLine in [System.IO.File]::ReadAllLines($resolvedInput)) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0) { continue }
    if (!$line.StartsWith(":")) { throw "Invalid Intel HEX line: $line" }

    $record = New-Object byte[] (($line.Length - 1) / 2)
    for ($i = 0; $i -lt $record.Length; $i++) {
        $record[$i] = [Convert]::ToByte($line.Substring(1 + 2 * $i, 2), 16)
    }

    $sum = 0
    foreach ($value in $record) { $sum = ($sum + $value) -band 0xff }
    if ($sum -ne 0) { throw "Intel HEX checksum failure: $line" }

    $count = $record[0]
    if ($record.Length -ne ($count + 5)) { throw "Invalid Intel HEX record length: $line" }
    $address = ([int]$record[1] -shl 8) -bor $record[2]
    $type = $record[3]

    if ($type -eq 0) {
        $absolute = $upperAddress + $address
        for ($i = 0; $i -lt $count; $i++) {
            $target = $absolute + $i
            if (($target -lt 0) -or ($target -ge $rom.Length)) {
                throw "IPC firmware data outside the 2 KiB 8049 ROM at 0x$($target.ToString('X'))."
            }
            $rom[$target] = $record[4 + $i]
            $written[$target] = $true
        }
    } elseif ($type -eq 1) {
        $eofSeen = $true
    } elseif ($type -eq 4) {
        if ($count -ne 2) { throw "Invalid extended linear address record." }
        $upperAddress = ((([int]$record[4] -shl 8) -bor $record[5]) -shl 16)
    }
}

if (!$eofSeen) { throw "Intel HEX EOF record is missing." }
if ($written -contains $false) { throw "The IPC firmware does not define all 2048 ROM bytes." }

$builder = [System.Text.StringBuilder]::new(6144)
foreach ($value in $rom) {
    [void]$builder.AppendFormat("{0:X2}`n", $value)
}

$fullOutput = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($fullOutput)) | Out-Null
[System.IO.File]::WriteAllText($fullOutput, $builder.ToString(), [System.Text.Encoding]::ASCII)

Write-Host ("IPC ROM converted: {0}" -f $fullOutput)
Write-Host "Output size: 2048 bytes"
