# Installs Hearthkeep (one folder since 0.3.0) into your WoW AddOns folder.
# It copies the Hearthkeep folder and removes only the old Hearthkeep_Alts, Hearthkeep_Modes
# and Hearthkeep_Bosses folders (now built in). Nothing else is touched. Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1
# Optional: -AddOns "C:\path\to\Interface\AddOns" to skip the search.
param([string]$AddOns, [string]$Branch = 'feature/allinone')
$ErrorActionPreference = 'Stop'

# A junction or symbolic link (for example a dev checkout linked into AddOns) is removed
# as a link only: a recursive delete would follow it and remove the files it points to.
function Remove-Folder([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        [IO.Directory]::Delete($item.FullName)
    } else {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}

if (-not $AddOns) {
    $roots = @("${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft") +
        ('C', 'D', 'E', 'F' | ForEach-Object { "${_}:\World of Warcraft"; "${_}:\Games\World of Warcraft" })
    $found = @()
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
                $candidate = Join-Path $_.FullName 'Interface\AddOns'
                if (Test-Path -LiteralPath $candidate) { $found += $candidate }
            }
        }
    }
    if ($found.Count -eq 1) {
        $AddOns = $found[0]
    } elseif ($found.Count -gt 1) {
        Write-Output 'Several AddOns folders found:'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Output ("  {0}) {1}" -f ($i + 1), $found[$i]) }
        $answer = "$(Read-Host 'Type the number of the Forever one')".Trim()
        $pick = 0
        if (-not [int]::TryParse($answer, [ref]$pick) -or $pick -lt 1 -or $pick -gt $found.Count) {
            Write-Output ("Not a number from 1 to {0}. Nothing was changed." -f $found.Count)
            exit 1
        }
        $AddOns = $found[$pick - 1]
    } else {
        $AddOns = Read-Host 'Paste the full path of your Interface\AddOns folder (create it if it does not exist)'
    }
}
# Only ever work inside a folder that really is ...\Interface\AddOns.
$AddOns = "$AddOns".Trim().Trim('"')
if (-not $AddOns) { Write-Output 'No folder given. Nothing was changed.'; exit 1 }
$AddOns = [IO.Path]::GetFullPath($AddOns).TrimEnd('\', '/')
if (-not $AddOns.EndsWith('\Interface\AddOns', [StringComparison]::OrdinalIgnoreCase)) {
    Write-Output "This is not an Interface\AddOns folder: $AddOns. Nothing was changed."
    exit 1
}
Write-Output "Installing into: $AddOns"
$old = @('Hearthkeep_Alts', 'Hearthkeep_Modes', 'Hearthkeep_Bosses') | Where-Object { Test-Path -LiteralPath (Join-Path $AddOns $_) }
if ($old) { Write-Output ("Old folders that will be removed (now inside Hearthkeep): " + ($old -join ', ')) }
if ((Read-Host 'Continue? (y/n)') -ne 'y') { Write-Output 'Cancelled. Nothing was changed.'; exit }
if (-not (Test-Path -LiteralPath $AddOns)) { New-Item -ItemType Directory -Path $AddOns | Out-Null }

$temp = Join-Path $env:TEMP ('hearthkeep-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$zip = Join-Path $temp 'hearthkeep.zip'
$url = "https://github.com/pepeipto/hearthkeep/archive/refs/heads/$Branch.zip"
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $temp
$source = Get-ChildItem -LiteralPath $temp -Directory | Select-Object -First 1
$from = Join-Path $source.FullName 'Hearthkeep'
if (-not (Test-Path -LiteralPath $from)) { throw 'Missing Hearthkeep in the download. Nothing was changed.' }
$target = Join-Path $AddOns 'Hearthkeep'
# Replace the folder so files removed in a new version do not linger.
if (Test-Path -LiteralPath $target) { Remove-Folder $target }
Copy-Item -LiteralPath $from -Destination $AddOns -Recurse -Force
Write-Output 'Copied Hearthkeep'
foreach ($folder in 'Hearthkeep_Alts', 'Hearthkeep_Modes', 'Hearthkeep_Bosses') {
    $path = Join-Path $AddOns $folder
    if (Test-Path -LiteralPath $path) { Remove-Folder $path; Write-Output "Removed old $folder" }
}
Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'Done. Start (or restart) the game, enter with a character and type /hk debug in the game chat.'
