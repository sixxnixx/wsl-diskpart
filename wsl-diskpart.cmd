@echo off
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl-diskpart.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wsl-diskpart.ps1" %*
)
exit /b %ERRORLEVEL%
