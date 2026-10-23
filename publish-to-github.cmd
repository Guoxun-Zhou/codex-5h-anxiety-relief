@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\publish-to-github.ps1"
if errorlevel 1 echo Publication did not complete. See the message above and docs/PUBLISH.zh-CN.md.
pause
