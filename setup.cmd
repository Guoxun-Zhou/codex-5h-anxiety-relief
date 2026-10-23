@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0monitor.ps1" -Mode Setup
if errorlevel 1 echo Setup failed. See the message above and README.
pause
