param(
    [string]$InputPath = 'src/companion/nanoql.xml',
    [string]$OutputPath = 'src/companion/nanoql_xml.hex',
    [int]$Capacity = 2048
)

$ErrorActionPreference = 'Stop'

$inputFile = Get-Item -LiteralPath $InputPath
$xml = [System.IO.File]::ReadAllBytes($inputFile.FullName)
$compressedStream = [System.IO.MemoryStream]::new()

try {
    $gzip = [System.IO.Compression.GZipStream]::new(
        $compressedStream,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )
    try {
        $gzip.Write($xml, 0, $xml.Length)
    } finally {
        $gzip.Dispose()
    }

    $compressed = $compressedStream.ToArray()
} finally {
    $compressedStream.Dispose()
}

if ($compressed.Length -gt $Capacity) {
    throw "Compressed configuration is $($compressed.Length) bytes; capacity is $Capacity bytes."
}

$lines = [string[]]::new($Capacity)
for ($index = 0; $index -lt $Capacity; $index++) {
    $value = if ($index -lt $compressed.Length) { $compressed[$index] } else { 0 }
    $lines[$index] = $value.ToString('x2')
}

$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.File]::WriteAllLines($outputFullPath, $lines, [System.Text.Encoding]::ASCII)

Write-Host "Generated $outputFullPath"
Write-Host "XML: $($xml.Length) bytes"
Write-Host "Gzip: $($compressed.Length) bytes"
Write-Host "Capacity: $Capacity bytes"
