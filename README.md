# Service Desk Tool

Lokalne narzędzie do diagnostyki Windows 10/11 i macOS. Czyszczenie i naprawa systemu są dostępne tylko w Windows. Skrypt nie wysyła raportów przez sieć i nie wymaga instalowania dodatkowych pakietów.

## Kod na GitHubie

Repozytorium zawiera tylko skrypty i dokumentację. Folder `reports/` powstaje przy pierwszym uruchomieniu i jest ignorowany przez Git, ponieważ raporty mogą zawierać dane użytkowników oraz stacji. Przed opublikowaniem zmian sprawdź wynik `git status` i nie dodawaj raportów przez `git add -f`.

Po pobraniu repozytorium uruchom odpowiedni plik startowy z poniższej tabeli. Na macOS pliki `.command` są zapisane jako wykonywalne w Git; przy kopiowaniu plików poza Git może być konieczne przywrócenie tego uprawnienia.

## Uruchomienie dwuklikiem

| System | Zwykłe uruchomienie | Wersja administracyjna |
|---|---|---|
| Windows 10/11 | `Start-Windows.cmd` | `Start-Windows-Admin.cmd` — monit UAC |
| macOS | `Start-macOS.command` | `Start-macOS-Admin.command` — Terminal poprosi o hasło konta z uprawnieniami administratora |

Skopiuj lub rozpakuj **cały folder** na stację. Pliki startowe otwierają menu i próbują dopasować okno do ramki HUD: około 81 × 20 znaków w Windows oraz 70 × 16 na macOS. Jeśli terminal nie pozwala zmienić rozmiaru, program nadal działa. Menu obsługuje strzałki, Enter, cyfry i Esc.

Na macOS oba pliki `.command` muszą zachować uprawnienie do wykonywania; dostarczony ZIP je zapisuje. Jeśli macOS blokuje plik pobrany z internetu, otwórz go z menu kontekstowego Findera zgodnie z zasadami organizacji. Wersja admin korzysta z `sudo`; nowy raport i ZIP po zakończeniu otrzymują właściciela, który uruchomił skrypt. Może być konieczne przyznanie Terminalowi dostępu do danych chronionych w ustawieniach prywatności macOS.

W Windows pliki startowe ustawiają `ExecutionPolicy Bypass` tylko dla uruchamianego procesu PowerShell. Polityka narzucona przez organizację może nadal zablokować skrypt. Przed pierwszym użyciem czynności czyszczących uruchom na maszynie testowej `./windows-service-desk.ps1 -SelfTest -Plain`; test czyści tylko własny katalog w `%TEMP%`.

## Zbieranie danych i logów

Po wybraniu sekcji ustaw okres od 1 do 168 godzin; domyślnie jest to 24 godziny. **Pełny raport** uruchamia wszystkie sekcje. Administrator może odczytać więcej źródeł, ale nie każda instalacja ma wszystkie wymienione logi.

| Sekcja macOS | Co zapisuje |
|---|---|
| System i sprzęt | Dane `system_profiler` o systemie i sprzęcie |
| Sieć i VPN | Interfejsy, DNS, trasy oraz do 3000 ostatnich wpisów z dziennika macOS dotyczących sieci i Network Extension |
| Dyski i wydajność | Wolne miejsce, pamięć i procesy |
| Aplikacje i aktualizacje | Lista aplikacji, pakietów i historia aktualizacji |
| Zdarzenia systemowe | Do 5000 ostatnich błędów i awarii z dziennika macOS oraz dostępne pliki `system.log`, `install.log` i raporty diagnostyczne użytkownika/systemu |
| FortiClient | Lokalne pliki logów Fortinet/FortiClient oraz do 5000 ostatnich wpisów procesów FortiClient z dziennika macOS |

Pliki macOS są kopiowane do `raw/mac-logs/`, a lokalne pliki FortiClient do `raw/forticlient/`. Każdy z tych katalogów ma `manifest.txt` ze źródłami, liczbą plików i błędami odczytu. Dodatkowe wyciągi z dziennika macOS trafiają do `network-events.txt`, `events.txt` i `forticlient-unified.txt`. Na Windows pełny raport, „Sieć i VPN” oraz „FortiClient” automatycznie dołączają dostępne lokalne logi FortiClient. Nie trzeba ręcznie wskazywać eksportu.

Kopiowanie plików FortiClient obejmuje maksymalnie 80 plików, 50 MB na plik i 250 MB łącznie. Kopiowanie innych plików logów macOS obejmuje maksymalnie 100 plików, 50 MB na plik i 200 MB łącznie. Filtr okresu dla plików używa daty ostatniej modyfikacji. Wyciągi z dziennika macOS mają limit liczby wpisów i czasu wykonania, więc przy bardzo dużym ruchu mogą nie obejmować całego okresu.

## Wynik

Każda sesja tworzy folder z `report.html`, surowymi wynikami w `raw/` i archiwum ZIP. Znajdziesz je w `reports/` obok skryptu. Możesz zmienić lokalizację raportów zmienną `SDT_REPORTS`. Przejrzyj pakiet przed dołączeniem go do zgłoszenia: nazwy użytkowników, adresy, dane sieciowe i treść logów mogą być poufne.

Automatycznie zebrane pliki FortiClient **nie są pełnym pakietem Diagnostic Tool** eksportowanym z interfejsu Fortinet. Jeśli źródło nie istnieje, logowanie w aplikacji jest wyłączone albo system odmawia dostępu, raport to pokaże. Skrypt nie zmienia ustawień FortiClient ani niczego nie wysyła.

## Czyszczenie Windows

Każdą operację zaznacza się osobno. Ostatni ekran wymaga wpisania `USUN`. Pliki używane przez system są pomijane. `cleanmgr` otwiera okno systemowe, w którym technik wybiera kategorie. Czyszczenie pobranych aktualizacji omija przebieg przy aktywnej aktualizacji i próbuje przywrócić wcześniej uruchomione usługi. `Prefetch` jest osobną, domyślnie niezaznaczoną pozycją.

DISM i SFC są w osobnym menu. Mogą trwać kilkadziesiąt minut; nie zamykaj wtedy terminala. Po niepowodzeniu DISM narzędzie pomija SFC i zapisuje przyczynę w raporcie.

## Sprawdzenie

Składnię skryptu macOS i zapytania `log show` sprawdzono na macOS, a kopiowanie plików i ZIP na próbnych danych. Wersja Windows przeszła kontrolę składni w PowerShell 7 na macOS; jej działania systemowe wymagają testu na Windows 10/11 przed użyciem produkcyjnym. Wersję admin macOS należy sprawdzić na stacji testowej z kontem administratora.
