param(
    [string]$GameRoot = $(if ($env:BET_GAME_ROOT) { $env:BET_GAME_ROOT } else { "F:\Steam\steamapps\common\Backrooms_Escape_Together" }),
    [string]$GameVersion = "BET-0.14.6",
    [string]$Stamp = (Get-Date -Format 'yyyy-MM-dd_HHmmss')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Win64 = Join-Path $GameRoot 'BET\Binaries\Win64'
$UE4SS = Join-Path $Win64 'ue4ss'
$Out = Join-Path $RepoRoot (Join-Path 'local_dumps' ("$GameVersion`_$Stamp"))

$objectDump = Join-Path $UE4SS 'UE4SS_ObjectDump.txt'
$headerDump = Join-Path $UE4SS 'CXXHeaderDump'
$log = Join-Path $UE4SS 'UE4SS.log'

if (!(Test-Path -LiteralPath $UE4SS)) { throw "UE4SS directory not found: $UE4SS" }
if (!(Test-Path -LiteralPath $objectDump)) { throw "Object dump not found: $objectDump. Launch the game through Steam and press Ctrl+J first." }
if (!(Test-Path -LiteralPath $headerDump)) { throw "CXXHeaderDump not found: $headerDump. Launch the game through Steam and press Ctrl+H first." }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
Copy-Item -LiteralPath $objectDump -Destination (Join-Path $Out 'UE4SS_ObjectDump.txt') -Force
Copy-Item -LiteralPath $headerDump -Destination (Join-Path $Out 'CXXHeaderDump') -Recurse -Force
if (Test-Path -LiteralPath $log) {
    Copy-Item -LiteralPath $log -Destination (Join-Path $Out 'UE4SS.log') -Force
}

$exe = Join-Path $Win64 'BETGameSteam-Win64-Shipping.exe'
$exeHash = if (Test-Path -LiteralPath $exe) { (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'missing' }
$objectHash = (Get-FileHash -LiteralPath (Join-Path $Out 'UE4SS_ObjectDump.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
$betHeader = Join-Path $Out 'CXXHeaderDump\BETGame.hpp'
$headerHash = if (Test-Path -LiteralPath $betHeader) { (Get-FileHash -LiteralPath $betHeader -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'missing' }

@"
# $GameVersion UE4SS dump

- Archived: $Stamp
- Game root: `$GameRoot`
- UE4SS dir: `$UE4SS`
- Shipping exe SHA256: `$exeHash`
- UE4SS_ObjectDump.txt SHA256: `$objectHash`
- CXXHeaderDump/BETGame.hpp SHA256: `$headerHash`
- Git policy: local only; ignored by `.gitignore`.

## How this snapshot was produced

1. Launch game through Steam with UE4SS installed.
2. At the menu/in game, press Ctrl+J for `UE4SS_ObjectDump.txt`.
3. Press Ctrl+H for `CXXHeaderDump/`.
4. Run `tools/archive_ue4ss_dump.ps1 -GameVersion "$GameVersion"` from the repo.

## Notes

Add manual observations here: game build number, menu reached, crashes, warnings, or UE4SS setting changes.
"@ | Set-Content -LiteralPath (Join-Path $Out 'manifest.md') -Encoding UTF8

Write-Host "Archived UE4SS dump to $Out"
