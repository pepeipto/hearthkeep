# Builds dist/Hearthkeep-<version>.zip containing the three addon folders.
# Run from anywhere: powershell -File scripts/build.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$toc = Join-Path $root 'Hearthkeep/Hearthkeep.toc'
$versionLine = Get-Content $toc | Where-Object { $_ -match '^##\s*Version:\s*(.+)$' } | Select-Object -First 1
if (-not $versionLine) { throw "No Version field in $toc" }
$version = ([regex]::Match($versionLine, '^##\s*Version:\s*(.+)$')).Groups[1].Value.Trim()

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipPath = Join-Path $dist "Hearthkeep-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($folder in 'Hearthkeep', 'Hearthkeep_Alts', 'Hearthkeep_Modes') {
        $base = Join-Path $root $folder
        Get-ChildItem -Path $base -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $relative)
        }
    }
}
finally {
    $zip.Dispose()
}

Write-Output $zipPath
