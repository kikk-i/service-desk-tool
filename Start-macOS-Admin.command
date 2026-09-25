#!/bin/bash
# Otwierany dwuklikiem w Finderze; główny launcher dopasowuje okno i uruchamia sudo.
HERE="$(cd "$(dirname "$0")" && pwd)" || exit 1
if [ ! -x "$HERE/Start-macOS.command" ]; then
  printf 'Brak wykonywalnego pliku Start-macOS.command w tym samym folderze.\n'
  printf 'Naciśnij Enter, aby zamknąć...'; IFS= read -r _
  exit 1
fi
"$HERE/Start-macOS.command" --admin
