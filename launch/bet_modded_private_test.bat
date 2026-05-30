@echo off
setlocal

set "CAP=%~1"
if "%CAP%"=="" set "CAP=12"

set "STEAM_EXE=F:\Steam\steam.exe"
set "GAME_ROOT=F:\Steam\steamapps\common\Backrooms_Escape_Together"
set "GAME_BIN=%GAME_ROOT%\BET\Binaries\Win64"
set "GAME_EXE=%GAME_BIN%\BETGameSteam-Win64-Shipping.exe"
set "APP_ID=2141730"

if not exist "%GAME_EXE%" (
  echo Could not find game executable:
  echo %GAME_EXE%
  exit /b 1
)

if not exist "%STEAM_EXE%" (
  echo Could not find Steam executable:
  echo %STEAM_EXE%
  exit /b 1
)

echo Launching Backrooms Escape Together through Steam with net.MaxPlayersOverride=%CAP%
echo This is a reversible private-lobby test; it does not modify game files.
echo If the game is already running, close it before launching this script.
echo.

pushd "%GAME_BIN%"
start "BET player-cap private test" "%STEAM_EXE%" -applaunch %APP_ID% -ExecCmds="net.MaxPlayersOverride %CAP%"
popd
