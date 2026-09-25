@echo off
setlocal
chcp 65001 >nul
set "LAUNCHER=%~dp0windows-admin-launch.ps1"
if not exist "%LAUNCHER%" (
  echo Brak pliku windows-admin-launch.ps1 w tym samym folderze.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"
if errorlevel 1 (
  echo.
  echo Nie udalo sie uruchomic programu jako administrator.
  pause
)
endlocal
