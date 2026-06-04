param(
    [string]$GameRoot = ""
)
$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Backup([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    return (Test-Path (Join-Path $p 'BET\Binaries\Win64\.BETPlayerCapBackup\manifest.txt'))
}
function Test-GameRoot([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    return (Test-Path (Join-Path $p 'BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe'))
}
function Find-Upward([string]$start, [scriptblock]$pred) {
    $d = $start
    for ($i = 0; $i -lt 10 -and -not [string]::IsNullOrWhiteSpace($d); $i++) {
        if (& $pred $d) { return $d }
        $parent = Split-Path -Parent $d
        if ($parent -eq $d) { break }
        $d = $parent
    }
    return ""
}
function Select-GameRootDialog() {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select your Backrooms: Escape Together game folder to uninstall BETPlayerCap from"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return ""
}

Write-Host 'BETPlayerCap v2.18.0 full package uninstaller'

# Prefer a folder that actually has our backup manifest; else any valid game root.
if (-not (Test-Backup $GameRoot)) {
    $g = Find-Upward $PackageRoot { param($p) Test-Backup $p }
    if (Test-Backup $g) { $GameRoot = $g }
}
if (-not (Test-Backup $GameRoot) -and -not (Test-GameRoot $GameRoot)) {
    $g = Find-Upward $PackageRoot { param($p) Test-GameRoot $p }
    if (Test-GameRoot $g) { $GameRoot = $g }
}
if (-not (Test-Backup $GameRoot) -and -not (Test-GameRoot $GameRoot)) {
    Write-Host 'Game folder not found. Opening a folder picker...'
    $picked = Select-GameRootDialog
    if (Test-GameRoot $picked) { $GameRoot = $picked }
    else { $up = Find-Upward $picked { param($p) Test-GameRoot $p }; if (Test-GameRoot $up) { $GameRoot = $up } }
}
if (-not (Test-GameRoot $GameRoot)) {
    throw "Could not locate the game folder.`nDrag the Backrooms_Escape_Together folder onto uninstall.bat, or pass it as an argument."
}

Write-Host "GameRoot: $GameRoot"
$Win64 = Join-Path $GameRoot 'BET\Binaries\Win64'
$BackupRoot = Join-Path $Win64 '.BETPlayerCapBackup'
$Manifest = Join-Path $BackupRoot 'manifest.txt'
$EngineIni = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini'
$EngineBackup = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini.bak_betcap_full'
$EngineState = Join-Path $BackupRoot 'engine_ini_state.txt'

if (!(Test-Path $BackupRoot)) { throw "No backup folder found: $BackupRoot`nNothing to uninstall, or it was installed manually." }
if (!(Test-Path $Manifest)) { throw "No manifest found: $Manifest`nRefusing to guess what to remove." }

Get-Content $Manifest | ForEach-Object {
    if ($_ -notmatch '^(B|N)\|(.*)$') { return }
    $kind = $Matches[1]; $rel = $Matches[2]
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
