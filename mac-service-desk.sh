#!/bin/bash
# Service Desk Tool — macOS diagnostics. No external dependencies.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPORTS="${SDT_REPORTS:-$ROOT/reports}"
mkdir -p "$REPORTS"
TTY=0; [ -t 0 ] && [ -t 1 ] && TTY=1
COLOR=0; [ "$TTY" -eq 1 ] && [ -z "${NO_COLOR:-}" ] && COLOR=1
CYAN=''; PURPLE=''; DIM=''; GREEN=''; RED=''; BG=''; RESET=''
if [ "$COLOR" -eq 1 ]; then
  CYAN=$'\033[38;2;151;211;222m'; PURPLE=$'\033[38;2;208;158;217m'
  DIM=$'\033[38;2;138;151;165m'; GREEN=$'\033[38;2;142;208;175m'
  RED=$'\033[38;2;235;150;150m'; BG=$'\033[48;2;23;29;37m'; RESET=$'\033[0m'
fi
ADMIN=0; [ "$(id -u)" -eq 0 ] && ADMIN=1
USER_HOME="${SDT_USER_HOME:-$HOME}"
START=0; WORK=''; HTML=''; STATUS=''; HOURS=24; SELECTED=''

escape_html() { printf '%s' "$1" | sed -e 's/\&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
safe_name() { printf '%s' "$1" | tr -cd '[:alnum:]_.-'; }
elapsed() { local n=$(( $(date +%s) - START )); printf '%02d:%02d' $((n/60)) $((n%60)); }
pause() { printf '\nNaciśnij Enter, aby wrócić...'; IFS= read -r _ || true; }
screen() {
  local title="$1" subtitle="$2" body="$3" width=62 head line pad timer fg rows=2
  if [ "$TTY" -eq 1 ]; then printf '\033[2J\033[H'; fi
  if [ "$TTY" -eq 1 ] && [ "$(tput cols 2>/dev/null || printf 80)" -ge 70 ]; then
    head=" $title  •  ADMIN: $( [ "$ADMIN" -eq 1 ] && printf TAK || printf NIE ) "
    [ "${#head}" -gt 63 ] && head="${head:0:62}…"
    pad=$((63-${#head}))
    line="$(printf '%*s' "$pad" '')"; line="${line// /─}"
    printf '%s%s╭─%s%s╮%s\n' "$BG" "$CYAN" "$head" "$line" "$RESET"
    line="$subtitle"; [ "${#line}" -gt "$width" ] && line="${line:0:61}…"
    pad=$((width-${#line}))
    printf '%s%s│%s %s%*s %s│%s\n' "$BG" "$CYAN" "$RESET$BG" "$line" "$pad" '' "$CYAN" "$RESET"
    printf '%s%s│%s %*s %s│%s\n' "$BG" "$CYAN" "$RESET$BG" "$width" '' "$CYAN" "$RESET"
    while IFS= read -r line; do
      [ "${#line}" -gt "$width" ] && line="${line:0:61}…"
      pad=$((width-${#line}))
      fg="$RESET$BG"
      case "$line" in '›'*|'◐'*|'◓'*|'◑'*|'◒'*) fg="$PURPLE$BG" ;; esac
      printf '%s%s│%s %s%*s %s│%s\n' "$BG" "$CYAN" "$fg" "$line" "$pad" '' "$CYAN" "$RESET"
      rows=$((rows+1))
    done <<< "$body"
    while [ "$rows" -lt 13 ]; do
      printf '%s%s│%s %*s %s│%s\n' "$BG" "$CYAN" "$RESET$BG" "$width" '' "$CYAN" "$RESET"
      rows=$((rows+1))
    done
    timer=" $( [ "$START" -gt 0 ] && elapsed || printf 00:00 ) "
    pad=$((64-${#timer}))
    line="$(printf '%*s' "$pad" '')"; line="${line// /─}"
    printf '%s%s╰%s%s╯%s\n' "$BG" "$CYAN" "$line" "$timer" "$RESET"
  else
    printf '\n%s [%s] ADMIN: %s%s\n%s\n' "$title" "$subtitle" "$( [ "$ADMIN" -eq 1 ] && printf TAK || printf NIE )" "$RESET" "$body"
  fi
}
menu() {
  local title="$1" subtitle="$2"; shift 2
  local choices=("$@") index=0 key seq i body
  while :; do
    body=''
    for ((i=0;i<${#choices[@]};i++)); do
      if [ "$i" -eq "$index" ]; then body="${body}›  $((i+1))  ${choices[i]}"; else body="${body}   $((i+1))  ${choices[i]}"; fi
      [ "$i" -lt $((${#choices[@]}-1)) ] && body="$body"$'\n'
    done
    body="$body"$'\n\n'"↑↓ wybierz   Enter otwórz   0 / Esc wróć"
    screen "$title" "$subtitle" "$body"
    IFS= read -rsn1 key || return 1
    case "$key" in
      '') MENU_CHOICE=$((index+1)); return 0 ;;
      0) return 1 ;;
      [1-9]) if [ "$key" -le "${#choices[@]}" ]; then MENU_CHOICE="$key"; return 0; fi ;;
      $'\033')
        IFS= read -rsn1 -t 1 seq || return 1
        if [ "$seq" = '[' ]; then
          IFS= read -rsn1 -t 1 seq || true
          [ "$seq" = A ] && index=$(( (index+${#choices[@]}-1)%${#choices[@]} ))
          [ "$seq" = B ] && index=$(( (index+1)%${#choices[@]} ))
        fi ;;
    esac
  done
}
make_report() {
  local kind="$1" stamp host
  stamp="$(date '+%Y%m%d-%H%M%S')"; host="$(safe_name "$(hostname -s)")"
  WORK="$REPORTS/${stamp}-${host}-${kind}"; mkdir -p "$WORK/raw"
  HTML="$WORK/report.html"; STATUS="$WORK/status.tsv"; : > "$STATUS"
  cat > "$HTML" <<'EOF'
<!doctype html><html lang="pl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Service Desk · raport</title>
<style>:root{color-scheme:dark}body{background:#171d25;color:#dae3e8;font:16px/1.5 -apple-system,BlinkMacSystemFont,Arial,sans-serif;max-width:980px;margin:auto;padding:32px}h1{color:#97d3de;letter-spacing:.08em}h2{font-size:1.1rem;color:#d09ed9}header,section{border:1px solid #769ba4;border-radius:8px;padding:20px;margin:0 0 16px}small{color:#a9b9c3}table{width:100%;border-collapse:collapse}th,td{text-align:left;border-bottom:1px solid #34434e;padding:10px;vertical-align:top}a{color:#a9dfea}code{color:#d09ed9;overflow-wrap:anywhere}.ok{color:#8ed0af}.error{color:#eb9696}.skip{color:#b5b9c2}</style>
<header><h1>SERVICE DESK / RAPORT</h1><p id="meta"></p><small>Pakiet zawiera dane techniczne. Przejrzyj go przed dołączeniem do zgłoszenia.</small></header>
<section><h2>Wyniki</h2><table><thead><tr><th>Etap</th><th>Status</th><th>Informacja</th><th>Dane</th></tr></thead><tbody>
EOF
  local meta
  meta="$(escape_html "$(date '+%Y-%m-%d %H:%M:%S %Z') · $(hostname) · macOS · administrator: $( [ "$ADMIN" -eq 1 ] && printf tak || printf nie )")"
  # Replace fixed placeholder with escaped metadata.
  sed -i '' "s|<p id=\"meta\"></p>|<p id=\"meta\">$meta</p>|" "$HTML"
}
record() {
  local name="$1" state="$2" info="$3" file="${4:-}" class=skip link='—'
  [ "$state" = gotowe ] && class=ok
  [ "$state" = błąd ] && class=error
  if [ -n "$file" ]; then link="<a href=\"raw/$(escape_html "$file")\">Otwórz</a>"; fi
  printf '<tr><td>%s</td><td class="%s">%s</td><td>%s</td><td>%s</td></tr>\n' "$(escape_html "$name")" "$class" "$(escape_html "$state")" "$(escape_html "$info")" "$link" >> "$HTML"
  printf '%s\t%s\t%s\n' "$name" "$state" "$info" >> "$STATUS"
}
finish_report() {
  printf '</tbody></table></section></html>\n' >> "$HTML"
  (cd "$REPORTS" && zip -q -r -X "$(basename "$WORK").zip" "$(basename "$WORK")")
  if [ "$ADMIN" -eq 1 ]; then
    case "${SUDO_UID:-}" in
      ''|*[!0-9]*) ;;
      *) chown -R "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$WORK" "$WORK.zip" 2>/dev/null || true ;;
    esac
  fi
  printf '\nRaport: %s\nZIP: %s.zip\nSprawdź zawartość przed dołączeniem do zgłoszenia.\n' "$HTML" "$WORK"
}
progress() {
  local title="$1" stage="$2" frame="$3"
  local symbols=('◐' '◓' '◑' '◒')
  screen "$title" "$stage" "${symbols[$frame]}  Trwa zbieranie danych..."
}
run_step() {
  local name="$1" file="$2" timeout="$3"; shift 3
  local pid start now frame=0 status=0
  "$@" > "$WORK/raw/$file" 2>&1 & pid=$!; start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    progress "$name" "ADMIN = WIĘCEJ DANYCH" "$frame"
    frame=$(( (frame+1)%4 )); sleep 0.2; now=$(date +%s)
    if [ $((now-start)) -ge "$timeout" ]; then
      pkill -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
      record "$name" błąd "Przekroczono limit ${timeout}s" "$file"; return
    fi
  done
  wait "$pid" || status=$?
  if [ "$status" -eq 0 ]; then
    case "$file" in
      events.txt|network-events.txt|forticlient-unified.txt)
        if [ "$(wc -l < "$WORK/raw/$file")" -le 1 ]; then
          record "$name" pominięte 'Brak wpisów w wybranym okresie' "$file"
        else
          record "$name" gotowe 'Zapisano wynik' "$file"
        fi ;;
      *) record "$name" gotowe 'Zapisano wynik' "$file" ;;
    esac
  else record "$name" błąd "Kod zakończenia: $status" "$file"; fi
}
collect_forti() {
  local hours="$1" root file size modified now cutoff count=0 checked=0 skipped=0 errors=0 bytes=0 index=0 name
  local dest="$WORK/raw/forticlient" manifest="$WORK/raw/forticlient/manifest.txt" max_bytes=$((250*1024*1024))
  local roots=( '/Library/Application Support/Fortinet/FortiClient/Logs' '/Library/Logs/Fortinet' '/Library/Logs/FortiClient' "$USER_HOME/Library/Logs/FortiClient" "$USER_HOME/Library/Application Support/Fortinet/FortiClient/Logs" )
  [ -n "${SDT_FORTI_LOG_ROOT:-}" ] && roots+=( "$SDT_FORTI_LOG_ROOT" )
  mkdir -p "$dest"; : > "$manifest"
  now=$(date +%s); cutoff=$((now-hours*3600))
  if [ -d /Applications/FortiClient.app ] || [ -d '/Applications/FortiClient VPN.app' ]; then
    record 'FortiClient' gotowe 'Wykryto aplikację'
  else
    record 'FortiClient' pominięte 'Nie wykryto aplikacji; sprawdzam dostępne pliki logów'
  fi
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    printf 'Źródło: %s\n' "$root" >> "$manifest"
    while IFS= read -r -d '' file; do
      checked=$((checked+1))
      size=$(stat -f %z "$file" 2>/dev/null) || { errors=$((errors+1)); continue; }
      modified=$(stat -f %m "$file" 2>/dev/null) || { errors=$((errors+1)); continue; }
      if [ "$modified" -lt "$cutoff" ] || [ "$size" -gt $((50*1024*1024)) ] || [ "$count" -ge 80 ] || [ $((bytes+size)) -gt "$max_bytes" ]; then
        skipped=$((skipped+1)); continue
      fi
      index=$((index+1)); printf -v name '%03d-%s' "$index" "$(safe_name "$(basename "$file")")"
      if cp -p "$file" "$dest/$name" 2>/dev/null; then
        count=$((count+1)); bytes=$((bytes+size))
        printf '%s ← %s (%s B)\n' "$name" "$file" "$size" >> "$manifest"
      else
        errors=$((errors+1)); printf 'Błąd odczytu: %s\n' "$file" >> "$manifest"
      fi
      progress 'FortiClient · logi lokalne' "Sprawdzono $checked · dołączono $count · $((bytes/1024/1024)) MB" "$((index%4))"
    done < <(find "$root" -type f -print0 2>> "$manifest")
  done
  [ "$checked" -gt 0 ] || printf 'Nie znaleziono dostępnych plików logów z ostatnich %s godzin.\n' "$hours" >> "$manifest"
  local state=pominięte
  [ "$errors" -gt 0 ] && state=błąd
  [ "$count" -gt 0 ] && state=gotowe
  record 'FortiClient · logi lokalne' "$state" "Dołączono $count plików ($((bytes/1024/1024)) MB); sprawdzono $checked; pominięto $skipped; błędy $errors. Okres: ${hours}h. To lokalne pliki, nie pełny pakiet Diagnostic Tool." 'forticlient/manifest.txt'
}
collect_file_logs() {
  local hours="$1" root file size modified now cutoff count=0 checked=0 skipped=0 errors=0 bytes=0 index=0 name
  local dest="$WORK/raw/mac-logs" manifest="$WORK/raw/mac-logs/manifest.txt" max_bytes=$((200*1024*1024))
  local roots=( '/var/log/system.log' '/var/log/install.log' '/Library/Logs/DiagnosticReports' "$USER_HOME/Library/Logs/DiagnosticReports" )
  [ -n "${SDT_MAC_LOG_ROOT:-}" ] && roots+=( "$SDT_MAC_LOG_ROOT" )
  mkdir -p "$dest"; : > "$manifest"
  now=$(date +%s); cutoff=$((now-hours*3600))
  for root in "${roots[@]}"; do
    [ -e "$root" ] || continue
    printf 'Źródło: %s\n' "$root" >> "$manifest"
    if [ -f "$root" ]; then
      local files=( "$root" )
      for file in "${files[@]}"; do
        copy_mac_log "$file"
      done
    else
      while IFS= read -r -d '' file; do
        copy_mac_log "$file"
      done < <(find "$root" -type f -print0 2>> "$manifest")
    fi
  done
  [ "$checked" -gt 0 ] || printf 'Nie znaleziono dostępnych plików logów.\n' >> "$manifest"
  local state=pominięte
  [ "$errors" -gt 0 ] && state=błąd
  [ "$count" -gt 0 ] && state=gotowe
  record 'Pliki logów macOS' "$state" "Dołączono $count plików ($((bytes/1024/1024)) MB); sprawdzono $checked; pominięto $skipped; błędy $errors. Okres: ${hours}h." 'mac-logs/manifest.txt'
}
copy_mac_log() {
  checked=$((checked+1))
  size=$(stat -f %z "$file" 2>/dev/null) || { errors=$((errors+1)); return; }
  modified=$(stat -f %m "$file" 2>/dev/null) || { errors=$((errors+1)); return; }
  if [ "$modified" -lt "$cutoff" ] || [ "$size" -gt $((50*1024*1024)) ] || [ "$count" -ge 100 ] || [ $((bytes+size)) -gt "$max_bytes" ]; then
    skipped=$((skipped+1)); return
  fi
  index=$((index+1)); printf -v name '%03d-%s' "$index" "$(safe_name "$(basename "$file")")"
  if cp -p "$file" "$dest/$name" 2>/dev/null; then
    count=$((count+1)); bytes=$((bytes+size))
    printf '%s ← %s (%s B)\n' "$name" "$file" "$size" >> "$manifest"
  else
    errors=$((errors+1)); printf 'Błąd odczytu: %s\n' "$file" >> "$manifest"
  fi
  progress 'Pliki logów macOS' "Sprawdzono $checked · dołączono $count · $((bytes/1024/1024)) MB" "$((index%4))"
}
collect() {
  local choice="$1" hours="$2"
  START=$(date +%s); make_report diagnostyka
  case "$choice" in
    1|2) run_step 'System i sprzęt' system.txt 45 system_profiler SPHardwareDataType SPSoftwareDataType ;;
  esac
  case "$choice" in
    1|3)
      run_step 'Sieć i VPN' network.txt 25 sh -c 'ifconfig; scutil --dns; netstat -rn; networksetup -listallhardwareports'
      run_step 'Zdarzenia sieci i VPN' network-events.txt 120 /bin/bash -c 'set -o pipefail; /usr/bin/log show --last "$1" --style compact --info --predicate "process == \"nesessionmanager\" OR process == \"neagent\" OR process == \"configd\" OR subsystem BEGINSWITH \"com.apple.networkextension\"" 2>&1 | tail -n 3000' _ "${hours}h" ;;
  esac
  case "$choice" in
    1|4) run_step 'Dyski i wydajność' performance.txt 25 sh -c 'df -h; vm_stat; top -l 1 -n 20' ;;
  esac
  case "$choice" in
    1|5) run_step 'Aplikacje i aktualizacje' software.txt 75 sh -c 'system_profiler SPApplicationsDataType; softwareupdate --history; pkgutil --pkgs' ;;
  esac
  case "$choice" in
    1|6)
      run_step 'Zdarzenia systemowe' events.txt 120 /bin/bash -c 'set -o pipefail; /usr/bin/log show --last "$1" --style compact --predicate "messageType == error OR messageType == fault" 2>&1 | tail -n 5000' _ "${hours}h"
      collect_file_logs "$hours" ;;
  esac
  case "$choice" in
    1|3|7)
      collect_forti "$hours"
      run_step 'FortiClient · dziennik macOS' forticlient-unified.txt 120 /bin/bash -c 'set -o pipefail; /usr/bin/log show --last "$1" --style compact --info --predicate "process == \"FortiClient\" OR process == \"FortiTray\" OR process == \"fctctld\" OR process == \"sslvpnd\" OR process == \"epctrl\"" 2>&1 | tail -n 5000' _ "${hours}h" ;;
  esac
  finish_report
}
main() {
  local c h input
  while :; do
    menu 'SERVICE DESK TOOL · macOS' 'Diagnostyka stacji użytkownika' 'Optymalizacja stacji [Windows]' 'Zbieranie danych i logów [ADMIN = WIĘCEJ]' 'Poprzednie raporty' || break
    c="$MENU_CHOICE"
    case "$c" in
      1) screen 'Optymalizacja stacji' 'Tylko Windows 10/11' 'Na macOS dostępne jest zbieranie danych i logów.'; pause ;;
      2)
        h=24
        menu 'DANE I LOGI' 'ADMIN = WIĘCEJ DANYCH' 'Pełny raport' 'System i sprzęt' 'Sieć i VPN' 'Dyski i wydajność' 'Aplikacje i aktualizacje' 'Zdarzenia systemowe' 'FortiClient · logi lokalne' || continue
        c="$MENU_CHOICE"
        printf 'Okres zdarzeń w godzinach [24, 1–168]: '; IFS= read -r input || true
        case "$input" in ''|*[!0-9]*) h=24 ;; *) if [ "$input" -ge 1 ] && [ "$input" -le 168 ]; then h="$input"; fi ;; esac
        collect "$c" "$h"; pause ;;
      3) printf '\nOstatnie raporty:\n'; find "$REPORTS" -maxdepth 1 -name '*.zip' -type f | sort -r | head -n 10; pause ;;
    esac
  done
}
main
