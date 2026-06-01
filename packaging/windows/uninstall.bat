@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if errorlevel 1 (
  echo.
  echo Uninstall failed. See messages above.
  pause
  exit /b 1
)
echo.
echo Uninstall complete.
pause
