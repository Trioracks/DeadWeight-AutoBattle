@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap\Launch-DeadWeightAutoBattle.ps1"
exit /b %errorlevel%
