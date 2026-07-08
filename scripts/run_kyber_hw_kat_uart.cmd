@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_kyber_hw_kat_uart.ps1" %*
exit /b %ERRORLEVEL%
