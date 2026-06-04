param(
    [string]$GameRoot = $(if ($env:BET_GAME_ROOT) { $env:BET_GAME_ROOT } else { "F:\Steam\steamapps\common\Backrooms_Escape_Together" }),
    [string]$Version = "v2.19.0"
)
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Win64 = Join-Path $GameRoot 'BET\Binaries\Win64'
$OutRoot = Join-Path $RepoRoot "release\BETPlayerCap-$Version-full"
$PayloadWin64 = Join-Path $OutRoot 'payload\Win64'
$PayloadConfig = Join-Path $OutRoot 'payload\Config'
$Dist = Join-Path $RepoRoot 'dist'
$ZipPath = Join-Path $Dist "BETPlayerCap-$Version-full.zip"

if (!(Test-Path (Join-Path $Win64 'dwmapi.dll'))) { throw "UE4SS proxy not found in $Win64" }
if (!(Test-Path (Join-Path $Win64 'ue4ss\UE4SS.dll'))) { throw "UE4SS.dll not found in $Win64\ue4ss" }

Remove-Item -LiteralPath $OutRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $PayloadWin64 'ue4ss\Mods') | Out-Null
New-Item -ItemType Directory -Force -Path $PayloadConfig | Out-Null
New-Item -ItemType Directory -Force -Path $Dist | Out-Null

# Only the UE4SS proxy loader. The boost_*/tbb* DLLs in the game's Win64 are the
# GAME's own runtime (they ship with the install and every player already has them);
# UE4SS 3.x is self-contained and does not need them. Bundling them is unnecessary
# and would overwrite each player's game files, so they are intentionally excluded.
Copy-Item -LiteralPath (Join-Path $Win64 'dwmapi.dll') -Destination (Join-Path $PayloadWin64 'dwmapi.dll') -Force

$ue4ss = Join-Path $PayloadWin64 'ue4ss'
New-Item -ItemType Directory -Force -Path $ue4ss | Out-Null
Copy-Item -LiteralPath (Join-Path $Win64 'ue4ss\UE4SS.dll') -Destination (Join-Path $ue4ss 'UE4SS.dll') -Force
Copy-Item -LiteralPath (Join-Path $Win64 'ue4ss\UE4SS-settings.ini') -Destination (Join-Path $ue4ss 'UE4SS-settings.ini') -Force
Copy-Item -LiteralPath (Join-Path $Win64 'ue4ss\LICENSE') -Destination (Join-Path $ue4ss 'LICENSE') -Force
Copy-Item -LiteralPath (Join-Path $Win64 'ue4ss\UE4SS_Signatures') -Destination (Join-Path $ue4ss 'UE4SS_Signatures') -Recurse -Force

$mods = Join-Path $ue4ss 'Mods'
Copy-Item -LiteralPath (Join-Path $Win64 'ue4ss\Mods\Keybinds') -Destination (Join-Path $mods 'Keybinds') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Win64 'ue4ss\Mods\shared') -Destination (Join-Path $mods 'shared') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'ue4ss_mods\BETPlayerCap') -Destination (Join-Path $mods 'BETPlayerCap') -Recurse -Force
@'
BETPlayerCap : 1

; Built-in keybinds, do not move up!
Keybinds : 1
'@ | Set-Content -Path (Join-Path $mods 'mods.txt') -Encoding UTF8
@'
[
  { "mod_name": "BETPlayerCap", "mod_enabled": true },
  { "mod_name": "Keybinds", "mod_enabled": true }
]
'@ | Set-Content -Path (Join-Path $mods 'mods.json') -Encoding UTF8

Copy-Item -LiteralPath (Join-Path $RepoRoot 'config\Engine.ini') -Destination (Join-Path $PayloadConfig 'Engine.ini') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\windows\install.bat') -Destination (Join-Path $OutRoot 'install.bat') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\windows\uninstall.bat') -Destination (Join-Path $OutRoot 'uninstall.bat') -Force
# The actual logic lives in .ps1 files with deliberately uncommon names so a user
# with file extensions hidden can't mistake them for the .bat and double-click the
# wrong one. The .bat files are the intended entry points and call these by name.
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\windows\betcap-installer.core.ps1') -Destination (Join-Path $OutRoot 'betcap-installer.core.ps1') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\windows\betcap-uninstaller.core.ps1') -Destination (Join-Path $OutRoot 'betcap-uninstaller.core.ps1') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\windows\README_INSTALL.txt') -Destination (Join-Path $OutRoot 'README_INSTALL.txt') -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\windows\README_INSTALL.zh-CN.txt') -Destination (Join-Path $OutRoot 'README_INSTALL.zh-CN.txt') -Force

Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $OutRoot -DestinationPath $ZipPath -Force
Write-Host "Built $ZipPath"
