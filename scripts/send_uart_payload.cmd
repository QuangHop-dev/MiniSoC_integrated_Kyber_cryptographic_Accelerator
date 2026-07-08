@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0send_uart_payload.ps1" %*
exit /b %ERRORLEVEL%
