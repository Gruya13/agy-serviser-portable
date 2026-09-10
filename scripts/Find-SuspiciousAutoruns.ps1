<#
.SYNOPSIS
    Triaza i pronalazenje sumnjivih autorun stavki, zakazanih zadataka i procesa.
.DESCRIPTION
    Skenira registry Run/RunOnce kljuceve, zakazane zadatke (Scheduled Tasks)
    i aktivne procese na postojanje sumnjivih putanja (Temp, AppData, Script pokretaci).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "           TRIAZA AUTORUN STAVKI I SUMNJIVIH PROCESA             " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

$suspiciousKeywords = @("temp", "appdata\\local\\temp", "wscript", "cscript", "cmd.exe /c", "-enc", "-windowstyle hidden", "powershell -e")

# 1. Provera Registry Run kljuceva
$runKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
)

Write-Host "`n[*] 1. Pregled Registry Run lokacija:" -ForegroundColor Yellow

foreach ($key in $runKeys) {
    if (Test-Path $key) {
        $props = Get-ItemProperty -Path $key
        $propNames = $props.PSObject.Properties.Name | Where-Object { $_ -notmatch "^PS" }
        foreach ($name in $propNames) {
            $val = $props.$name
            $isSuspicious = $false
            foreach ($kw in $suspiciousKeywords) {
                if ($val -like "*$kw*") { $isSuspicious = $true; break }
            }

            if ($isSuspicious) {
                Write-Host "  [!] SUMNJIVO: [$name] u $key" -ForegroundColor Red
                Write-Host "      Komanda: $val" -ForegroundColor Yellow
            } else {
                Write-Host "  [OK] [$name] -> $val" -ForegroundColor Gray
            }
        }
    }
}

# 2. Provera Scheduled Tasks koji se pokrecu iz sumnjivih lokacija
Write-Host "`n[*] 2. Pregled Scheduled Tasks koji pokrecu skripte ili izvrsne fajlove iz korisnickih foldera:" -ForegroundColor Yellow
try {
    $tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.Author -notlike "*Microsoft*" }
    $foundSuspiciousTask = $false

    foreach ($task in $tasks) {
        $action = $task.Actions | Select-Object -First 1
        $execPath = "$($action.Execute) $($action.Arguments)"

        foreach ($kw in $suspiciousKeywords) {
            if ($execPath -like "*$kw*") {
                $foundSuspiciousTask = $true
                Write-Host "  [!] SUMNJIV ZADATAK: $($task.TaskName) (Putanja: $($task.TaskPath))" -ForegroundColor Red
                Write-Host "      Izvrsava: $execPath" -ForegroundColor Yellow
                break
            }
        }
    }

    if (-not $foundSuspiciousTask) {
        Write-Host "  [OK] Nisu pronadjeni ocigledno sumnjivi zakazani zadaci." -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Nije moguce ocitati Scheduled Tasks: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 3. Pregled procesa koji se pokrecu iz Temp direktorijuma
Write-Host "`n[*] 3. Aktivni procesi pokrenuti iz Temp direktorijuma:" -ForegroundColor Yellow
$tempProcesses = Get-Process | Where-Object {
    $_.Path -and ($_.Path -like "*\Temp\*" -or $_.Path -like "*\AppData\Local\Temp\*")
}

if ($tempProcesses) {
    foreach ($p in $tempProcesses) {
        Write-Host "  [!] PROCES IZ TEMP-a: $($p.Name) (PID: $($p.Id)) -> $($p.Path)" -ForegroundColor Red
    }
} else {
    Write-Host "  [OK] Nema aktivnih procesa pokrenutih iz privremenih direktorijuma." -ForegroundColor Green
}

Write-Host "==================================================================" -ForegroundColor Cyan
