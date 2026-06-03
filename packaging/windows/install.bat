@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0betcap-installer.core.ps1" %*
if errorlevel 1 (
  echo.
  echo Install failed. See messages above.
  pause
  exit /b 1
)
echo.
echo Install complete.
pause
