#requires -Version 5.1
<#[Service Desk Tool] Lokalna diagnostyka i optymalizacja Windows 10/11.
Uruchamiaj wyłącznie na stacjach, na których masz uprawnienie do obsługi.
#>
param([switch]$Plain,[switch]$SelfTest,[switch]$FitWindow)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Reports = if ($env:SDT_REPORTS) { $env:SDT_REPORTS } else { Join-Path $script:Root 'reports' }
New-Item -ItemType Directory -Force -Path $script:Reports | Out-Null
$script:Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Dopasuj klasyczne okno konsoli do ramki HUD; hosty bez obsługi zmiany rozmiaru zachowują dotychczasowy układ.
if ($FitWindow -and -not [Console]::IsOutputRedirected) {
    try {
        $targetWidth=[Math]::Min(81,[Console]::LargestWindowWidth)
        $targetHeight=[Math]::Min(20,[Console]::LargestWindowHeight)
        if ($targetWidth -ge 72 -and $targetHeight -ge 15) {
            [Console]::SetBufferSize([Math]::Max($targetWidth,[Console]::BufferWidth),[Math]::Max($targetHeight,[Console]::BufferHeight))
            [Console]::SetWindowSize($targetWidth,$targetHeight)
        }
    } catch { }
}
$script:Rich = -not $Plain -and -not [Console]::IsOutputRedirected -and [Console]::WindowWidth -ge 72 -and [Console]::WindowHeight -ge 15
$script:Results = New-Object System.Collections.ArrayList
$script:Work = ''
$script:Started = Get-Date
$script:Frame = 0
$script:Queue = @()

function Html([string]$Text) { return [System.Net.WebUtility]::HtmlEncode($Text) }
function Clock { return '{0:mm\:ss}' -f ((Get-Date) - $script:Started) }
function Screen([string]$Title, [string]$Sub, [string[]]$Lines) {
    if ($script:Rich) {
        try { [Console]::SetCursorPosition(0,0) } catch { [Console]::Clear() }
        $width = [Math]::Min([Console]::WindowWidth - 1, 80)
        $inside = $width - 4
        $adminText = if ($script:Admin) { 'ADMIN: TAK' } else { 'ADMIN: NIE' }
        $head = (' {0}  •  {1}' -f $Title, $adminText)
        if ($head.Length -gt ($width-5)) { $head = $head.Substring(0,$width-5) }
        $top = '╭─' + $head + ('─' * [Math]::Max(0,$width-$head.Length-3)) + '╮'
        Write-Host $top -ForegroundColor Cyan
        $rows = @($Sub, '') + $Lines
        $minRows = [Math]::Max(10,[Math]::Min(18,[Console]::WindowHeight-4))
        for ($i=0; $i -lt $minRows; $i++) {
            $line = if ($i -lt $rows.Count) { [string]$rows[$i] } else { '' }
            if ($line.Length -gt $inside) { $line = $line.Substring(0,$inside-1) + '…' }
            $tone = if ($line.StartsWith('›') -or $line.StartsWith('◐') -or $line.StartsWith('◓') -or $line.StartsWith('◑') -or $line.StartsWith('◒')) { 'Magenta' } else { 'Gray' }
            Write-Host '│ ' -ForegroundColor Cyan -NoNewline
            Write-Host $line.PadRight($inside) -ForegroundColor $tone -NoNewline
            Write-Host ' │' -ForegroundColor Cyan
        }
        $foot = ' ' + (Clock) + ' '
        Write-Host ('╰' + ('─' * [Math]::Max(0,$width-$foot.Length-2)) + $foot + '╯') -ForegroundColor Cyan
    } else {
        Write-Host "`n$Title  [$Sub]  ADMIN: $(if ($script:Admin) {'TAK'} else {'NIE'})"
        $Lines | ForEach-Object { Write-Host $_ }
    }
}
function Menu([string]$Title, [string]$Sub, [string[]]$Items) {
    $pos = 0
    while ($true) {
        $lines = @()
        for ($i=0; $i -lt $Items.Count; $i++) {
            $mark = if ($i -eq $pos) { '›' } else { ' ' }
            $lines += ('{0}  {1}  {2}' -f $mark,($i+1),$Items[$i])
        }
        $lines += '', '↑↓ wybierz    Enter otwórz    0 / Esc wróć'
        Screen $Title $Sub $lines
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $pos = ($pos + $Items.Count - 1) % $Items.Count }
            'DownArrow' { $pos = ($pos + 1) % $Items.Count }
            'Enter' { return ($pos+1) }
            'Escape' { return 0 }
            'D0' { return 0 }
            'NumPad0' { return 0 }
            default {
                if ($key.KeyChar -match '^[1-9]$') {
                    $num = [int]([string]$key.KeyChar)
                    if ($num -le $Items.Count) { return $num }
                }
            }
        }
    }
}
function Pause-Menu { Write-Host "`nEnter — powrót do menu"; [void][Console]::ReadLine() }
function New-Report([string]$Kind) {
    $script:Results.Clear()
    $script:Queue = @()
    $script:Started = Get-Date
    $hostName = $env:COMPUTERNAME -replace '[^A-Za-z0-9_.-]',''
    $name = '{0}-{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$hostName,$Kind
    $script:Work = Join-Path $script:Reports $name
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Work 'raw') | Out-Null
}
function Add-Result([string]$Name,[string]$State,[string]$Info,[string]$File='') {
    [void]$script:Results.Add([pscustomobject]@{Name=$Name;State=$State;Info=$Info;File=$File;Time=(Get-Date).ToString('HH:mm:ss')})
}
function Show-Progress([string]$Name,[string]$Detail) {
    $symbols = @('◐','◓','◑','◒')
    $symbol = $symbols[$script:Frame % 4]; $script:Frame++
    $lines = @("$symbol  $Name",$Detail,'')
    foreach ($item in $script:Queue) {
        $result = @($script:Results | Where-Object { $_.Name -eq $item } | Select-Object -Last 1)
        $state = if ($result.Count) { $result[0].State } elseif ($item -eq $Name) { 'trwa' } else { 'oczekuje' }
        $lines += ('{0,-10} {1}' -f $state,$item)
    }
    Screen 'SERVICE DESK TOOL · PRACA' 'Zapis wyników do lokalnego raportu' $lines
}
function Invoke-Collect([string]$Name,[string]$File,[scriptblock]$Script,[int]$Timeout=60,[object[]]$Arguments=@()) {
    $job = Start-Job -ScriptBlock $Script -ArgumentList $Arguments
    $begin = Get-Date
    try {
        while ($job.State -eq 'Running') {
            Show-Progress $Name ('Trwa • {0} s' -f [int]((Get-Date)-$begin).TotalSeconds)
            Start-Sleep -Milliseconds 250
            $job = Get-Job -Id $job.Id
            if (((Get-Date)-$begin).TotalSeconds -ge $Timeout) {
                Stop-Job -Id $job.Id
                Add-Result $Name 'błąd' "Przekroczono limit ${Timeout}s" $File
                return
            }
        }
        $data = Receive-Job -Id $job.Id -ErrorAction Continue 2>&1 | Out-String -Width 220
        [IO.File]::WriteAllText((Join-Path $script:Work "raw\$File"),$data,[Text.UTF8Encoding]::new($false))
        if ($job.State -eq 'Completed') { Add-Result $Name 'gotowe' 'Zapisano wynik' $File }
        else { Add-Result $Name 'błąd' 'Polecenie nie zostało ukończone' $File }
    } catch {
        Add-Result $Name 'błąd' $_.Exception.Message $File
    } finally { Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue }
}
function Write-Report([string]$Kind,[string]$Summary='') {
    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $adminText = if ($script:Admin) {'tak'} else {'nie'}
    $html = @"
<!doctype html><html lang="pl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Service Desk · raport</title>
<style>:root{color-scheme:dark}body{background:#171d25;color:#dae3e8;font:16px/1.5 Segoe UI,Arial,sans-serif;max-width:980px;margin:auto;padding:32px}h1{color:#97d3de;letter-spacing:.08em}h2{font-size:1.1rem;color:#d09ed9}header,section{border:1px solid #769ba4;border-radius:8px;padding:20px;margin:0 0 16px}small{color:#a9b9c3}table{width:100%;border-collapse:collapse}th,td{text-align:left;border-bottom:1px solid #34434e;padding:10px;vertical-align:top}a{color:#a9dfea}.ok{color:#8ed0af}.error{color:#eb9696}.skip{color:#b5b9c2}</style>
<header><h1>SERVICE DESK / RAPORT</h1><p>$(Html "$time · $env:COMPUTERNAME · Windows · administrator: $adminText")</p><small>Pakiet zawiera dane techniczne. Przejrzyj go przed dołączeniem do zgłoszenia.</small></header>
<section><h2>$(Html $Kind)</h2><p>$(Html $Summary)</p><table><thead><tr><th>Czas</th><th>Etap</th><th>Status</th><th>Informacja</th><th>Dane</th></tr></thead><tbody>
"@
    foreach ($r in $script:Results) {
        $class = if ($r.State -eq 'gotowe') {'ok'} elseif ($r.State -eq 'błąd') {'error'} else {'skip'}
        $link = '—'; if ($r.File -and (Test-Path (Join-Path $script:Work "raw\$($r.File)"))) { $link = '<a href="raw/' + (Html $r.File) + '">Otwórz</a>' }
        $html += '<tr><td>'+(Html $r.Time)+'</td><td>'+(Html $r.Name)+'</td><td class="'+$class+'">'+(Html $r.State)+'</td><td>'+(Html $r.Info)+'</td><td>'+$link+"</td></tr>`n"
    }
    $html += '</tbody></table></section></html>'
    [IO.File]::WriteAllText((Join-Path $script:Work 'report.html'),$html,[Text.UTF8Encoding]::new($false))
    $zip = "$($script:Work).zip"
    Compress-Archive -Path $script:Work -DestinationPath $zip -Force
    Write-Host "`nRaport: $(Join-Path $script:Work 'report.html')"
    Write-Host "ZIP: $zip"
    Write-Host 'Przejrzyj pakiet przed dołączeniem do zgłoszenia.'
}
function Get-FreeBytes {
    $drive = New-Object IO.DriveInfo ($env:SystemDrive + '\')
    return [long]$drive.AvailableFreeSpace
}
function Size-Text([long]$Bytes) { return ('{0:N1} MB' -f ($Bytes/1MB)) }
function Get-SafeTree([string]$Path) {
    $files=New-Object System.Collections.ArrayList
    $dirs=New-Object System.Collections.ArrayList
    $stack=New-Object System.Collections.Stack
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $current=[string]$stack.Pop()
        foreach ($entry in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($entry.FullName.StartsWith($script:Reports,[StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($entry.FullName.StartsWith($script:Root,[StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($entry.PSIsContainer) { [void]$dirs.Add($entry); $stack.Push($entry.FullName) }
            else { [void]$files.Add($entry) }
        }
    }
    return [pscustomobject]@{Files=$files.ToArray();Dirs=$dirs.ToArray()}
}
function Get-Estimate([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{Count=0;Bytes=0L} }
    $files = (Get-SafeTree $Path).Files
    $bytes = 0L; foreach ($file in $files) { $bytes += $file.Length }
    return [pscustomobject]@{Count=$files.Count;Bytes=$bytes}
}
function Clear-Contents([string]$Path,[string]$Label) {
    Show-Progress $Label 'Sprawdzanie i usuwanie plików'
    if (-not (Test-Path -LiteralPath $Path)) { Add-Result $Label 'pominięte' 'Katalog nie istnieje'; return }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    if ($resolved.Length -lt 10 -or $resolved -eq $env:SystemDrive+'\' -or $script:Root.StartsWith($resolved,[StringComparison]::OrdinalIgnoreCase)) {
        Add-Result $Label 'błąd' 'Niebezpieczna ścieżka docelowa'; return
    }
    $count=0; $removed=0; $skipped=0; $bytes=0L
    $tree = Get-SafeTree $resolved
    $files = $tree.Files
    foreach ($file in $files) {
        $count++
        try {
            $len=$file.Length; Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++; $bytes+=$len
        } catch { $skipped++ }
        if ($count % 20 -eq 0) { Show-Progress $Label "Sprawdzono $count · usunięto $removed · odzyskano $(Size-Text $bytes)" }
    }
    foreach ($dir in @($tree.Dirs | Sort-Object { $_.FullName.Length } -Descending)) {
        try { Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop } catch { }
    }
    Add-Result $Label 'gotowe' "Sprawdzono $count, usunięto $removed, pominięto $skipped, odzyskano $(Size-Text $bytes)"
}
function Clear-UpdateDownload {
    $label='Windows Update · Download'; $path=Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    $active = @(Get-Process -Name 'TiWorker','MoUsoCoreWorker','TrustedInstaller' -ErrorAction SilentlyContinue)
    if ($active.Count -gt 0) { Add-Result $label 'pominięte' 'Trwa obsługa aktualizacji systemu'; return }
    $pending=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    if (@($pending | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) { Add-Result $label 'pominięte' 'System oczekuje na restart po aktualizacji'; return }
    $original=@{}
    foreach ($name in @('wuauserv','BITS')) {
        $service=Get-Service -Name $name -ErrorAction Stop
        $original[$name]=$service.Status
    }
    try {
        foreach ($name in $original.Keys) {
            if ($original[$name] -eq 'Running') {
                Stop-Service -Name $name -Force -ErrorAction Stop
                (Get-Service -Name $name).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
            }
        }
        Clear-Contents $path $label
    } catch { Add-Result $label 'błąd' $_.Exception.Message }
    finally {
        foreach ($name in $original.Keys) {
            if ($original[$name] -eq 'Running') {
                try { Start-Service -Name $name -ErrorAction Stop } catch { Add-Result $name 'błąd' ('Nie przywrócono usługi: '+$_.Exception.Message) }
            }
        }
    }
}
function Invoke-External([string]$Name,[string]$Exe,[string[]]$Args) {
    $out=Join-Path $script:Work ('raw\'+($Name -replace '[^A-Za-z0-9]','_')+'.txt')
    $err="$out.stderr.txt"
    try {
        $proc=Start-Process -FilePath $Exe -ArgumentList $Args -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
        while (-not $proc.HasExited) { Show-Progress $Name "Trwa · PID $($proc.Id) · $(Clock)"; Start-Sleep -Milliseconds 300; $proc.Refresh() }
        $status=if ($proc.ExitCode -eq 0) {'gotowe'} else {'błąd'}
        Add-Result $Name $status "Kod zakończenia: $($proc.ExitCode)" ([IO.Path]::GetFileName($out))
        return $proc.ExitCode
    } catch { Add-Result $Name 'błąd' $_.Exception.Message; return -1 }
}
function Choose-Cleanup {
    $items=@(
        [pscustomobject]@{Name='%TEMP%';Badge='BEZ ADMINA';Path=$env:TEMP;Key='temp'},
        [pscustomobject]@{Name='Windows Temp';Badge='ADMIN WYMAGANY';Path=(Join-Path $env:SystemRoot 'Temp');Key='wtemp'},
        [pscustomobject]@{Name='Oczyszczanie dysku';Badge='ADMIN WYMAGANY';Path='';Key='cleanmgr'},
        [pscustomobject]@{Name='Windows Update · Download';Badge='ADMIN WYMAGANY';Path=(Join-Path $env:SystemRoot 'SoftwareDistribution\Download');Key='update'},
        [pscustomobject]@{Name='Prefetch';Badge='ADMIN WYMAGANY · zwykle mały zysk';Path=(Join-Path $env:SystemRoot 'Prefetch');Key='prefetch'}
    )
    $sizes=New-Object System.Collections.ArrayList
    foreach ($item in $items) {
        Screen 'OPTYMALIZACJA · ANALIZA' 'Liczenie plików przed wyborem' @("◐  $($item.Name)")
        $estimate=$null
        if ($item.Path -and ($script:Admin -or $item.Badge -eq 'BEZ ADMINA')) { $estimate=Get-Estimate $item.Path }
        [void]$sizes.Add($estimate)
    }
    $selected=@($false,$false,$false,$false,$false); $pos=0
    while ($true) {
        $lines=@()
        for ($i=0; $i -lt $items.Count; $i++) {
            $mark=if ($i -eq $pos) {'›'} else {' '}
            $check=if ($selected[$i]) {'x'} else {' '}
            $extra=if ($sizes[$i]) { ' · '+(Size-Text $sizes[$i].Bytes) } else { '' }
            $lines += "${mark} [$check] $($items[$i].Name) · $($items[$i].Badge)$extra"
        }
        $lines += '','↑↓ / 1–5 wybierz   Spacja zaznacz   Enter dalej   Esc wróć'
        Screen 'OPTYMALIZACJA · WYBÓR' 'Czynności są domyślnie niezaznaczone' $lines
        $key=[Console]::ReadKey($true)
        if ($key.Key -eq 'Escape') { return }
        if ($key.Key -eq 'Enter') { break }
        if ($key.Key -eq 'UpArrow') { $pos=($pos+$items.Count-1)%$items.Count }
        elseif ($key.Key -eq 'DownArrow') { $pos=($pos+1)%$items.Count }
        elseif ($key.Key -eq 'Spacebar') { $selected[$pos]=-not $selected[$pos] }
        elseif ($key.KeyChar -match '^[1-5]$') { $pos=[int]([string]$key.KeyChar)-1; $selected[$pos]=-not $selected[$pos] }
    }
    $chosen=New-Object System.Collections.ArrayList
    for ($i=0; $i -lt $items.Count; $i++) { if ($selected[$i]) { [void]$chosen.Add($items[$i]) } }
    if ($chosen.Count -eq 0) { return }
    $summary=@($chosen | ForEach-Object { "• $($_.Name) [$($_.Badge)]" })
    $summary += '','Pliki są usuwane trwale. Wpisz USUN, aby wykonać.'
    Screen 'POTWIERDZENIE' 'Wybrane czynności' $summary
    $answer=[Console]::ReadLine()
    if ($answer -cne 'USUN') { Write-Host 'Anulowano.'; Pause-Menu; return }
    New-Report 'optymalizacja'; $before=Get-FreeBytes
    $script:Queue = @($chosen | ForEach-Object { $_.Name })
    foreach ($item in $chosen) {
        if ($item.Badge -like 'ADMIN*' -and -not $script:Admin) {
            Add-Result $item.Name 'pominięte' 'Administrator wymagany. Uruchom PowerShell jako administrator.'; continue
        }
        switch ($item.Key) {
            'temp' { Clear-Contents $item.Path $item.Name }
            'wtemp' { Clear-Contents $item.Path $item.Name }
            'prefetch' { Clear-Contents $item.Path $item.Name }
            'update' { Clear-UpdateDownload }
            'cleanmgr' {
                try {
                    Show-Progress 'Oczyszczanie dysku' 'Wybierz kategorie w oknie systemowym.'
                    $proc=Start-Process -FilePath 'cleanmgr.exe' -ArgumentList @('/d',$env:SystemDrive) -PassThru
                    while (-not $proc.HasExited) { Show-Progress 'Oczyszczanie dysku' 'Czekam na zamknięcie okna systemowego.'; Start-Sleep -Milliseconds 300; $proc.Refresh() }
                    Add-Result 'Oczyszczanie dysku' 'gotowe' "Okno zamknięto (kod $($proc.ExitCode)); wybrane kategorie nie są wykrywane przez skrypt"
                } catch { Add-Result 'Oczyszczanie dysku' 'błąd' $_.Exception.Message }
            }
        }
    }
    $after=Get-FreeBytes; $delta=$after-$before
    Write-Report 'Optymalizacja Windows' "Wolne miejsce: $(Size-Text $before) → $(Size-Text $after); zmiana: $(Size-Text $delta)."
    Pause-Menu
}
function Repair-System {
    if (-not $script:Admin) { Screen 'NAPRAWA SYSTEMU' 'ADMIN WYMAGANY' @('Uruchom PowerShell jako administrator.'); Pause-Menu; return }
    Screen 'NAPRAWA SYSTEMU' 'DISM → SFC' @('Operacja może trwać kilkadziesiąt minut.','DISM może pobierać dane z Windows Update.','','Wpisz NAPRAW, aby rozpocząć.')
    if ([Console]::ReadLine() -cne 'NAPRAW') { return }
    New-Report 'naprawa'
    $script:Queue = @('DISM RestoreHealth','SFC Scannow')
    $dism=Invoke-External 'DISM RestoreHealth' 'dism.exe' @('/Online','/Cleanup-Image','/RestoreHealth')
    if ($dism -eq 0) { [void](Invoke-External 'SFC Scannow' 'sfc.exe' @('/scannow')) }
    else { Add-Result 'SFC Scannow' 'pominięte' 'DISM nie zakończył się powodzeniem' }
    Write-Report 'Naprawa systemu' 'Kolejność: DISM RestoreHealth, następnie SFC Scannow.'
    Pause-Menu
}
function Collect-FortiLogs([int]$Hours) {
    $label='FortiClient · logi lokalne'
    $roots=New-Object System.Collections.ArrayList
    if ($env:ProgramFiles) { [void]$roots.Add((Join-Path $env:ProgramFiles 'Fortinet\FortiClient\logs\trace')) }
    $programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) { [void]$roots.Add((Join-Path $programFilesX86 'Fortinet\FortiClient\logs\trace')) }
    if ($env:APPDATA) { [void]$roots.Add((Join-Path $env:APPDATA 'FortiClient\logs\trace')) }
    # Przy uruchomieniu jako inne konto administratora odczytaj też profil zalogowanego użytkownika.
    try {
        $loggedOn=(Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($loggedOn) {
            $sid=([Security.Principal.NTAccount]$loggedOn).Translate([Security.Principal.SecurityIdentifier]).Value
            $profile=Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$sid'" -ErrorAction Stop
            if ($profile -and $profile.LocalPath) { [void]$roots.Add((Join-Path $profile.LocalPath 'AppData\Roaming\FortiClient\logs\trace')) }
        }
    } catch { }
    if ($env:SDT_FORTI_LOG_ROOT) { [void]$roots.Add($env:SDT_FORTI_LOG_ROOT) }
    $dest=Join-Path $script:Work 'raw\forticlient'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $manifest=Join-Path $dest 'manifest.txt'
    $cutoff=(Get-Date).AddHours(-$Hours)
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $count=0; $checked=0; $skipped=0; $errors=0; $bytes=0L
    $limit=250MB
    $index=0
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $resolved=(Resolve-Path -LiteralPath $root).ProviderPath
        if (-not $seen.Add($resolved)) { continue }
        Add-Content -LiteralPath $manifest -Value "Źródło: $resolved" -Encoding UTF8
        try { Get-ChildItem -LiteralPath $resolved -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null; $files=@((Get-SafeTree $resolved).Files | Sort-Object LastWriteTime -Descending) }
        catch { Add-Content -LiteralPath $manifest -Value "Błąd odczytu: $($_.Exception.Message)" -Encoding UTF8; $errors++; continue }
        foreach ($file in $files) {
            $checked++
            if ($file.LastWriteTime -lt $cutoff -or $file.Length -gt 50MB -or $count -ge 80 -or ($bytes+$file.Length) -gt $limit) { $skipped++; continue }
            $index++
            $name=('{0:D3}-{1}' -f $index,($file.Name -replace '[^A-Za-z0-9_.-]','_'))
            try {
                Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dest $name) -ErrorAction Stop
                $count++; $bytes+=$file.Length
                Add-Content -LiteralPath $manifest -Value ("$name ← $($file.FullName) ($($file.Length) B)") -Encoding UTF8
            } catch {
                $errors++
                Add-Content -LiteralPath $manifest -Value ("Błąd: $($file.FullName): $($_.Exception.Message)") -Encoding UTF8
            }
            Show-Progress $label "Sprawdzono $checked · dołączono $count · $(Size-Text $bytes)"
        }
    }
    if (-not (Test-Path -LiteralPath $manifest)) { Add-Content -LiteralPath $manifest -Value 'Nie znaleziono katalogu lokalnych logów FortiClient.' -Encoding UTF8 }
    $state=if ($count -gt 0) {'gotowe'} elseif ($errors -gt 0) {'błąd'} else {'pominięte'}
    Add-Result $label $state "Dołączono $count plików ($(Size-Text $bytes)); sprawdzono $checked; pominięto $skipped; błędy $errors. Okres: ${Hours}h. To lokalne pliki, nie pełny pakiet Diagnostic Tool." 'forticlient/manifest.txt'
}
function Collect-Data {
    $choice=Menu 'DANE I LOGI' 'ADMIN = WIĘCEJ DANYCH' @('Pełny raport','System i sprzęt','Sieć i VPN','Dyski i wydajność','Aplikacje i aktualizacje','Zdarzenia systemowe','FortiClient · logi lokalne')
    if ($choice -eq 0) { return }
    $raw=Read-Host 'Okres zdarzeń w godzinach [24, 1–168]'
    $hours=24; $parsed=0
    if ([int]::TryParse($raw,[ref]$parsed) -and $parsed -ge 1 -and $parsed -le 168) { $hours=$parsed }
    New-Report 'diagnostyka'
    $script:Queue = @()
    if ($choice -in @(1,2)) { $script:Queue += 'System i sprzęt' }
    if ($choice -in @(1,3)) { $script:Queue += 'Sieć i VPN' }
    if ($choice -in @(1,4)) { $script:Queue += 'Dyski i wydajność' }
    if ($choice -in @(1,5)) { $script:Queue += 'Aplikacje i aktualizacje' }
    if ($choice -in @(1,6)) { $script:Queue += 'Zdarzenia systemowe' }
    if ($choice -in @(1,3,7)) { $script:Queue += 'FortiClient · logi lokalne' }
    if ($choice -in @(1,2)) {
        Invoke-Collect 'System i sprzęt' 'system.txt' {
            $failed = @()
            foreach ($class in @('Win32_OperatingSystem','Win32_ComputerSystem','Win32_BIOS','Win32_Processor','Win32_PhysicalMemory')) {
                "=== $class ==="
                try {
                    Get-CimInstance -ClassName $class -ErrorAction Stop | Format-List * | Out-String -Width 220
                } catch {
                    "BŁĄD $($class): $($_.Exception.Message)"
                    $failed += $class
                }
            }
            if ($failed.Count -gt 0) { throw ('Nie udało się pobrać: ' + ($failed -join ', ')) }
        } 45
    }
    if ($choice -in @(1,3)) {
        Invoke-Collect 'Sieć i VPN' 'network.txt' { ipconfig /all; route print; Get-NetAdapter | Format-Table -AutoSize; Get-DnsClientServerAddress | Format-Table -AutoSize; Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue | Format-List * } 40
    }
    if ($choice -in @(1,4)) {
        Invoke-Collect 'Dyski i wydajność' 'performance.txt' { Get-Volume | Format-Table -AutoSize; Get-CimInstance Win32_LogicalDisk | Format-Table -AutoSize; Get-Process | Sort-Object CPU -Descending | Select-Object -First 30 Name,CPU,WorkingSet,Id | Format-Table -AutoSize } 40
    }
    if ($choice -in @(1,5)) {
        Invoke-Collect 'Aplikacje i aktualizacje' 'software.txt' { Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 100 | Format-Table -AutoSize; Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName | Format-Table -AutoSize } 50
    }
    if ($choice -in @(1,6)) {
        $since=(Get-Date).AddHours(-$hours)
        Invoke-Collect 'Zdarzenia systemowe' 'events.txt' { param($From,$WithSecurity)
            Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$From;Level=1,2,3} -MaxEvents 500 -ErrorAction SilentlyContinue | Format-List TimeCreated,Id,ProviderName,LevelDisplayName,Message
            Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$From;Level=1,2,3} -MaxEvents 500 -ErrorAction SilentlyContinue | Format-List TimeCreated,Id,ProviderName,LevelDisplayName,Message
            if ($WithSecurity) { Get-WinEvent -FilterHashtable @{LogName='Security';StartTime=$From} -MaxEvents 300 -ErrorAction SilentlyContinue | Format-List TimeCreated,Id,ProviderName,Message }
        } 75 @($since,$script:Admin)
    }
    if ($choice -in @(1,3,7)) { Collect-FortiLogs $hours }
    Write-Report 'Diagnostyka stacji' "Okres zdarzeń: ${hours}h."
    Pause-Menu
}
if ($SelfTest) {
    $fixture=Join-Path $env:TEMP ('SDT-selftest-'+[guid]::NewGuid().ToString('N'))
    try {
        $nested=Join-Path $fixture 'nested'
        New-Item -ItemType Directory -Force -Path $nested | Out-Null
        [IO.File]::WriteAllText((Join-Path $nested 'fixture.txt'),'safe test')
        Clear-Contents $fixture 'Test czyszczenia'
        if (-not (Test-Path -LiteralPath $fixture) -or (Get-ChildItem -LiteralPath $fixture -Force | Measure-Object).Count -ne 0) { throw 'Test czyszczenia nie powiódł się' }
        Write-Host 'OK: usunięto wyłącznie plik testowy; katalog docelowy pozostał.'
    } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    return
}
while ($true) {
    $choice=Menu 'SERVICE DESK TOOL · WINDOWS' 'Diagnostyka i optymalizacja stacji' @('Optymalizacja stacji','Zbieranie danych i logów','Poprzednie raporty','Naprawa systemu · ADMIN WYMAGANY')
    switch ($choice) {
        0 { return }
        1 { Choose-Cleanup }
        2 { Collect-Data }
        3 { Get-ChildItem -LiteralPath $script:Reports -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,LastWriteTime | Format-Table -AutoSize; Pause-Menu }
        4 { Repair-System }
    }
}
