@echo off
setlocal
chcp 65001 >nul
set "SCRIPT=%~dp0windows-service-desk.ps1"
if not exist "%SCRIPT%" (
  echo Brak pliku windows-service-desk.ps1 w tym samym folderze.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -FitWindow
if errorlevel 1 (
  echo.
  echo Program zakonczyl sie bledem. Sprawdz komunikat powyzej.
  pause
)
endlocal
