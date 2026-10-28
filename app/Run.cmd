@echo off
rem IT Toolkit launcher - runs as admin, ExecutionPolicy Bypass for this process only
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Start-Toolkit.ps1"
