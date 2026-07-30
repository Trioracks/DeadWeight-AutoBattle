@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DeadWeightAutoBattle.ps1"
exit /b %errorlevel%
