#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$main = Join-Path $PSScriptRoot 'windows-service-desk.ps1'
if (-not (Test-Path -LiteralPath $main -PathType Leaf)) { throw 'Brak pliku windows-service-desk.ps1.' }
$exe = Join-Path $PSHOME 'powershell.exe'
$args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -FitWindow' -f $main
Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $PSScriptRoot -Verb RunAs -ErrorAction Stop | Out-Null
