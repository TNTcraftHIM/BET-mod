param(
    [string]$GameRoot = ""
)
$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadWin64 = Join-Path $PackageRoot 'payload\Win64'
$PayloadEngineIni = Join-Path $PackageRoot 'payload\Config\Engine.ini'

function Test-GameRoot([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    return (Test-Path (Join-Path $p 'BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe'))
}

# Walk up from a starting dir to find the game root. Handles the recommended flow:
# the user extracts this package directly INTO the game folder, so the package sits
# somewhere under <GameRoot>\... and we find <GameRoot> by walking up.
function Find-GameRootUpward([string]$start) {
    $d = $start
    for ($i = 0; $i -lt 10 -and -not [string]::IsNullOrWhiteSpace($d); $i++) {
        if (Test-GameRoot $d) { return $d }
        $parent = Split-Path -Parent $d
        if ($parent -eq $d) { break }
        $d = $parent
    }
    return ""
}

function Select-GameRootDialog() {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select your Backrooms: Escape Together game folder (the one containing BET\Binaries\Win64)"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return ""
}

Write-Host 'BETPlayerCap v2.17.0 full package installer'

# Resolution order: explicit arg -> extracted-in-place (walk up) -> folder picker.
if (-not (Test-GameRoot $GameRoot)) { $GameRoot = Find-GameRootUpward $PackageRoot }
if (-not (Test-GameRoot $GameRoot)) {
    Write-Host 'Game folder not found from this location. Opening a folder picker...'
    Write-Host 'Select your Backrooms_Escape_Together folder (or its BET / Win64 subfolder).'
    $picked = Select-GameRootDialog
    if (Test-GameRoot $picked) { $GameRoot = $picked }
    else { $up = Find-GameRootUpward $picked; if (Test-GameRoot $up) { $GameRoot = $up } }
}
if (-not (Test-GameRoot $GameRoot)) {
    throw "No valid game folder selected.`nExpected BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe under it.`nTip: extract this package into your Backrooms_Escape_Together folder and run install.bat again."
}

Write-Host "GameRoot: $GameRoot"
$Win64 = Join-Path $GameRoot 'BET\Binaries\Win64'
$BackupRoot = Join-Path $Win64 '.BETPlayerCapBackup'
$Manifest = Join-Path $BackupRoot 'manifest.txt'
$EngineIni = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini'
$EngineBackup = Join-Path $env:LOCALAPPDATA 'BET\Saved\Config\Windows\Engine.ini.bak_betcap_full'

if (!(Test-Path $PayloadWin64)) { throw "Missing package payload: $PayloadWin64" }

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EngineIni) | Out-Null
if (Test-Path $Manifest) { Remove-Item $Manifest -Force }

function Backup-IfExists([string]$TargetPath) {
    if (Test-Path $TargetPath) {
        $rel = (Resolve-Path -LiteralPath $TargetPath).Path.Substring($Win64.Length).TrimStart('\')
        $backupPath = Join-Path $BackupRoot $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
        Add-Content -Path $Manifest -Value ("B|" + $rel)
    } else {
        $rel = $TargetPath.Substring($Win64.Length).TrimStart('\')
        Add-Content -Path $Manifest -Value ("N|" + $rel)
    }
}

Get-ChildItem -LiteralPath $PayloadWin64 -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($PayloadWin64.Length).TrimStart('\')
    Backup-IfExists (Join-Path $Win64 $rel)
}
Write-Host 'Copying UE4SS runtime + BETPlayerCap mod...'
Copy-Item -Path (Join-Path $PayloadWin64 '*') -Destination $Win64 -Recurse -Force

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

Write-Host 'Installed. Launch the game through Steam. Only the host needs this package.'
Write-Host 'Keybinds: Ctrl+G gather, Ctrl+J reload, Ctrl+K/L prev/next, Ctrl+O probe, Ctrl+P board, Ctrl+Arrows nudge.'
