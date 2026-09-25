#!/bin/bash
# Finder opens .command files in Terminal. Keep the script path relative to this launcher.
HERE="$(cd "$(dirname "$0")" && pwd)" || exit 1
cd "$HERE" || exit 1
if [ ! -f "$HERE/mac-service-desk.sh" ]; then
  printf 'Brak pliku mac-service-desk.sh w tym samym folderze.\n'
  printf 'Naciśnij Enter, aby zamknąć...'; IFS= read -r _
  exit 1
fi
# Finder uruchamia .command w Terminal.app. Dopasuj tylko kartę tego procesu.
if [ -t 0 ] && [ "${TERM_PROGRAM:-}" = Apple_Terminal ] && command -v osascript >/dev/null 2>&1; then
  current_tty="$(tty)"
  /usr/bin/osascript - "$current_tty" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set targetTTY to item 1 of argv
  tell application "Terminal"
    repeat with targetWindow in windows
      repeat with targetTab in tabs of targetWindow
        if (tty of targetTab) is targetTTY then
          set number of columns of targetTab to 70
          set number of rows of targetTab to 16
          return
        end if
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
fi
if [ "${1:-}" = '--admin' ] && [ "$(id -u)" -ne 0 ]; then
  report_dir="${SDT_REPORTS:-$HERE/reports}"
  mkdir -p "$report_dir" || exit 1
  printf 'Wersja administracyjna: podaj hasło konta z uprawnieniami administratora.\n'
  /usr/bin/sudo /usr/bin/env SDT_USER_HOME="$HOME" SDT_REPORTS="$report_dir" /bin/bash "$HERE/mac-service-desk.sh"
else
  /bin/bash "$HERE/mac-service-desk.sh"
fi
status=$?
if [ "$status" -ne 0 ]; then
  printf '\nProgram zakończył się błędem (kod %s).\n' "$status"
  printf 'Naciśnij Enter, aby zamknąć...'; IFS= read -r _
fi
exit "$status"
