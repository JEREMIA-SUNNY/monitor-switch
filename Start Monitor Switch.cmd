@echo off
rem Starts Monitor Switch in the system tray with no window.
rem Keep this file in the same folder as MonitorSwitch.ps1.
start "" "%SystemRoot%\System32\conhost.exe" --headless "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0MonitorSwitch.ps1"
