param(
    [string]$GameRoot = ""
)
$ErrorActionPreference = 'Stop'

function Find-DefaultGameRoot() {
    $candidates = @(
        "F:\Steam\steamapps\common\Backrooms_Escape_Together",
        "C:\Program Files (x86)\Steam\steamapps\common\Backrooms_Escape_Together",
        "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together",
        "E:\SteamLibrary\steamapps\common\Backrooms_Escape_Together",
        "F:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'BET\Binaries\Win64\.BETPlayerCapBackup\manifest.txt')) { return $c }
    }
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe')) { return $c }
    }
    return ""
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) { $GameRoot = Find-DefaultGameRoot }
if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    throw "Could not auto-detect the game folder.`nDrag the Backrooms_Escape_Together folder onto uninstall.bat, or pass it as an argument."
}

$Win64 = Join-Path $GameRoot 'BET\Binaries\Win64'
$BackupRoot = Join-Path $Win64 '.BETPlayerCapBackup'
$Manifest = Join-Path $BackupRoot 'manifest.txt'
$EngineIni = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini'
$EngineBackup = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini.bak_betcap_full'
$EngineState = Join-Path $BackupRoot 'engine_ini_state.txt'

Write-Host 'BETPlayerCap v2.14 full package uninstaller'
Write-Host "GameRoot: $GameRoot"

if (!(Test-Path $BackupRoot)) {
    throw "No backup folder found: $BackupRoot`nNothing to uninstall, or the package was installed manually."
}
if (!(Test-Path $Manifest)) {
    throw "No manifest found: $Manifest`nRefusing to guess what to remove."
}

# Restore/remove Win64 files according to manifest.
Get-Content $Manifest | ForEach-Object {
    if ($_ -notmatch '^(B|N)\|(.*)$') { return }
    $kind = $Matches[1]
    $rel = $Matches[2]
    $dst = Join-Path $Win64 $rel
    $bak = Join-Path $BackupRoot $rel
    if ($kind -eq 'B') {
        if (Test-Path $bak) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath $bak -Destination $dst -Force
        }
    } elseif ($kind -eq 'N') {
        if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Force }
    }
}

# Restore/remove Engine.ini.
if (Test-Path $EngineState) {
    $state = (Get-Content $EngineState -Raw).Trim()
    if ($state -eq 'backup' -and (Test-Path $EngineBackup)) {
        Copy-Item -LiteralPath $EngineBackup -Destination $EngineIni -Force
        Remove-Item -LiteralPath $EngineBackup -Force
        Write-Host "Restored Engine.ini backup: $EngineIni"
    } elseif ($state -eq 'new') {
        if (Test-Path $EngineIni) { Remove-Item -LiteralPath $EngineIni -Force }
        Write-Host "Removed Engine.ini installed by package: $EngineIni"
    }
}

Remove-Item -LiteralPath $BackupRoot -Recurse -Force
Write-Host 'Uninstalled and restored backups.'
