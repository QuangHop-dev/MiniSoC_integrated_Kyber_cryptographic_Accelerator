@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_firmware_gui.ps1" %*
exit /b %ERRORLEVEL%
