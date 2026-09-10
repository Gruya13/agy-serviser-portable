<#
.SYNOPSIS
    Triaza kriticnih gresaka i padova sistema iz Windows Event Log-a.
.DESCRIPTION
    Filtrira Critical (1) i Error (2) zapise iz System i Application dnevnika
    za poslednjih N sati. Fokusira se na hardverske padove, disk greske,
    WHEA prijave i BSOD rušenja.
#>

[CmdletBinding()]
param (
    [int]$Hours = 24,
    [int]$MaxEntries = 15
)

$ErrorActionPreference = "SilentlyContinue"
$startTime = (Get-Date).AddHours(-$Hours)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "         WINDOWS EVENT LOG TRIAZA (POSLEDNJIH $Hours h)              " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Specijalni fokus: BSOD, Kernel-Power, WHEA i Disk greske
$criticalProviders = @(
    "Microsoft-Windows-Kernel-Power",
    "Microsoft-Windows-WHEA-Logger",
    "BugCheck",
    "disk",
    "ntfs",
    "storahci",
    "nvme",
    "volmgr"
)

Write-Host "`n[*] Analiza kriticnih hardverskih i sistemskih indikatora:" -ForegroundColor Yellow

foreach ($provider in $criticalProviders) {
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = $provider
            StartTime = $startTime
        } -ErrorAction SilentlyContinue

        if ($events) {
            $count = $events.Count
            Write-Host "  [!] Izvor: $provider - Pronadjeno $count dogadjaja!" -ForegroundColor Red
            # Prikaz najnovijeg dogadjaja
            $latest = $events[0]
            $msg = ($latest.Message -replace "`r`n", " ") -replace "`n", " "
            if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
            Write-Host "      Vreme: $($latest.TimeCreated) | ID: $($latest.Id) | $msg" -ForegroundColor Gray
        }
    } catch {}
}

# 2. Opsta triaza System dnevnika (Critical i Error)
Write-Host "`n[*] Najnovije kriticne greske u System dnevniku:" -ForegroundColor Yellow
try {
    $systemErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 1, 2
        StartTime = $startTime
    } -MaxEvents $MaxEntries -ErrorAction SilentlyContinue

    if ($systemErrors) {
        foreach ($evt in $systemErrors) {
            $levelName = if ($evt.Level -eq 1) { "CRITICAL" } else { "ERROR" }
            $color = if ($evt.Level -eq 1) { "Magenta" } else { "Red" }
            $cleanMsg = ($evt.Message -replace "`r`n", " ") -replace "`n", " "
            if ($cleanMsg.Length -gt 130) { $cleanMsg = $cleanMsg.Substring(0, 127) + "..." }
            Write-Host "  [$levelName] $($evt.TimeCreated.ToString('HH:mm:ss')) | $($evt.ProviderName) (ID: $($evt.Id))" -ForegroundColor $color
            Write-Host "    $cleanMsg" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [OK] Nema zabelezenih kriticnih gresaka u System dnevniku za ovaj period." -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Nije moguce ocitati System log: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 3. Kriticne greske u Application dnevniku
Write-Host "`n[*] Najnovije greske u Application dnevniku (padovi aplikacija):" -ForegroundColor Yellow
try {
    $appErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Level = 1, 2
        StartTime = $startTime
    } -MaxEvents 8 -ErrorAction SilentlyContinue

    if ($appErrors) {
        foreach ($evt in $appErrors) {
            $cleanMsg = ($evt.Message -replace "`r`n", " ") -replace "`n", " "
            if ($cleanMsg.Length -gt 130) { $cleanMsg = $cleanMsg.Substring(0, 127) + "..." }
            Write-Host "  [APP ERROR] $($evt.TimeCreated.ToString('HH:mm:ss')) | $($evt.ProviderName) (ID: $($evt.Id))" -ForegroundColor Red
            Write-Host "    $cleanMsg" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [OK] Nema zabelezenih gresaka u Application dnevniku." -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Nije moguce ocitati Application log: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "==================================================================" -ForegroundColor Cyan
