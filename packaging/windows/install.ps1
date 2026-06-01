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
        if (Test-Path (Join-Path $c 'BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe')) { return $c }
    }
    return ""
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) { $GameRoot = Find-DefaultGameRoot }
if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    throw "Could not auto-detect the game folder.`nFind it in Steam: Manage > Browse local files, then drag the Backrooms_Escape_Together folder onto install.bat."
}

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadWin64 = Join-Path $PackageRoot 'payload\Win64'
$PayloadEngineIni = Join-Path $PackageRoot 'payload\Config\Engine.ini'
$Win64 = Join-Path $GameRoot 'BET\Binaries\Win64'
$Exe = Join-Path $Win64 'BETGameSteam-Win64-Shipping.exe'
$BackupRoot = Join-Path $Win64 '.BETPlayerCapBackup'
$Manifest = Join-Path $BackupRoot 'manifest.txt'
$EngineIni = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini'
$EngineBackup = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini.bak_betcap_full'

Write-Host 'BETPlayerCap v2.14 full package installer'
Write-Host "GameRoot: $GameRoot"

if (!(Test-Path $Exe)) {
    throw "Could not find game executable: $Exe`nPass the game root path as an argument, e.g. install.bat ""D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"""
}
if (!(Test-Path $PayloadWin64)) { throw "Missing package payload: $PayloadWin64" }

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EngineIni) | Out-Null
if (Test-Path $Manifest) { Remove-Item $Manifest -Force }

function Backup-IfExists([string]$TargetPath) {
    if (Test-Path $TargetPath) {
        $rel = Resolve-Path -LiteralPath $TargetPath | ForEach-Object { $_.Path.Substring($Win64.Length).TrimStart('\') }
        $backupPath = Join-Path $BackupRoot $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
        Add-Content -Path $Manifest -Value ("B|" + $rel)
    } else {
        $rel = $TargetPath.Substring($Win64.Length).TrimStart('\')
        Add-Content -Path $Manifest -Value ("N|" + $rel)
    }
}

# Backup every file we will overwrite/create under Win64, then copy payload.
Get-ChildItem -LiteralPath $PayloadWin64 -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($PayloadWin64.Length).TrimStart('\')
    $dst = Join-Path $Win64 $rel
    Backup-IfExists $dst
}
Write-Host 'Copying UE4SS runtime + BETPlayerCap mod...'
Copy-Item -Path (Join-Path $PayloadWin64 '*') -Destination $Win64 -Recurse -Force

# Engine.ini anti-lag config, separate user config backup.
if (Test-Path $PayloadEngineIni) {
    if (Test-Path $EngineIni) {
        Copy-Item -LiteralPath $EngineIni -Destination $EngineBackup -Force
        Set-Content -Path (Join-Path $BackupRoot 'engine_ini_state.txt') -Value 'backup'
    } else {
        Set-Content -Path (Join-Path $BackupRoot 'engine_ini_state.txt') -Value 'new'
    }
    Copy-Item -LiteralPath $PayloadEngineIni -Destination $EngineIni -Force
    Write-Host "Installed anti-lag Engine.ini: $EngineIni"
}

Write-Host 'Installed.'
Write-Host 'Launch the game through Steam. Only the host needs this package.'
Write-Host 'Keybinds: Ctrl+G gather, Ctrl+J reload, Ctrl+K/L prev/next, Ctrl+O probe, Ctrl+P board, Ctrl+Arrows nudge.'
