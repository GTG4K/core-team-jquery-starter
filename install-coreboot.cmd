@echo off
echo Installing coreboot to %LOCALAPPDATA%\coreboot ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0coreboot.ps1" -Install
pause
