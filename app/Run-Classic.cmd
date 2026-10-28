@echo off
rem Classic WPF window (fallback)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Start-Classic.ps1"
