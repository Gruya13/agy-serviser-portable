<#
.SYNOPSIS
    PowerShell integracioni i unit testovi za Sync-ServiceHub.ps1 (ADR-0003).
.DESCRIPTION
    Verifikuje:
    1. Parsiranje Markdown profila i servisnih izveštaja (DEVICE_INFO.md, SERVISNI_DNEVNIK.md, IZVESTAJ_DIJAGNOSTIKE.md).
    2. Offline rad: Cuvanje u pending_sync/ kada Hub nije dostupan.
    3. Online rad (ako je Hub dostupan): Pre-flight pull, Post-flight push i Flush pending reda.
.PARAMETER HubUrl
    Opcioni URL aktivnog ServisHub servera (podrazumevano http://localhost:8000).
#>

[CmdletBinding()]
param (
    [string]$HubUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path $PSScriptRoot -Parent
$syncScript = Join-Path $scriptRoot "scripts\Sync-ServiceHub.ps1"

if (-not (Test-Path $syncScript)) {
    Write-Error "[X] Nije pronadjen scripts\Sync-ServiceHub.ps1!"
    return
}

$testPassed = 0
$testFailed = 0

function Assert-Equal($actual, $expected, $testName) {
    if ($actual -eq $expected) {
        Write-Host "  [PASS] $testName" -ForegroundColor Green
        $script:testPassed++
    } else {
        Write-Host "  [FAIL] $testName" -ForegroundColor Red
        Write-Host "         Ocekivano: '$expected', Dobijeno: '$actual'" -ForegroundColor Yellow
        $script:testFailed++
    }
}

function Assert-True($condition, $testName) {
    if ($condition) {
        Write-Host "  [PASS] $testName" -ForegroundColor Green
        $script:testPassed++
    } else {
        Write-Host "  [FAIL] $testName" -ForegroundColor Red
        $script:testFailed++
    }
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "      POKRETANJE TESTOVA: Sync-ServiceHub.ps1 (ADR-0003)          " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Priprema privremenog radnog foldera za mock uredjaj
# -----------------------------------------------------------------------------
$testGuid = [guid]::NewGuid().ToString().Substring(0, 8)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "agy_test_$testGuid"
$testDevTag = "HP_ProBook_450_G8_5CD$testGuid"
$testDevFolder = Join-Path $tempRoot "devices\$testDevTag"
$testReportsFolder = Join-Path $testDevFolder "reports"
$testPendingFolder = Join-Path $tempRoot "pending_sync"

New-Item -ItemType Directory -Path $testReportsFolder -Force | Out-Null
New-Item -ItemType Directory -Path $testPendingFolder -Force | Out-Null

try {
    # 1. Kreiranje mockup datoteka
    $deviceInfoContent = @"
# Servisni Karton Uredjaja: $testDevTag

- **Oznaka uredjaja (DeviceTag):** `$testDevTag`
- **Proizvodjac:** HP
- **Model racunara / ploce:** ProBook 450 G8 (Ploca: 881D)
- **Serijski broj:** `5CD$testGuid`
- **Hardverski UUID:** 4C4C4544-004B-4810-8037-B3C04F345832
- **Naziv u sistemu (ComputerName):** TEST-PC
- **Poslednja sinhronizacija:** 2026-10-09 15:30:00

---

## Hardverska Specifikacija

| Komponenta | Podaci |
| :--- | :--- |
| **Procesor (CPU)** | Intel Core i5-1135G7 |
| **Radna memorija (RAM)** | 16.0 GB |
| **Graficka karta (GPU)** | Intel Iris Xe Graphics |
| **Skladiste (Diskovi)** | KIOXIA NVMe 512GB (477 GB) |
| **Operativni sistem** | Windows 11 Pro - Build 22631 |
| **BIOS verzija** | T70 Ver. 01.14.00 |
"@
    [System.IO.File]::WriteAllText((Join-Path $testDevFolder "DEVICE_INFO.md"), $deviceInfoContent, [System.Text.Encoding]::UTF8)

    $dnevnikContent = @"
# Servisni Dnevnik Intervencija: $testDevTag

---

### [Datum: 2026-10-09 15:30:00] - Zamena paste i ciscenje hladnjaka
- **Status:** COMPLETED
- **Alati:** Get-DiskHealth.ps1, Get-EventLogTriage.ps1
- **Nalaz:** Temperature stabilne, nema throttlinga.
"@
    [System.IO.File]::WriteAllText((Join-Path $testDevFolder "SERVISNI_DNEVNIK.md"), $dnevnikContent, [System.Text.Encoding]::UTF8)

    $reportContent = @"
# Zavrsni Izvestaj Servisne Dijagnostike

- **Uredjaj:** HP ProBook 450 G8
- **Serijski broj:** 5CD$testGuid
- **Primarni uzrok (Root Cause):** Pregrevanje procesora usled sasusene termalne paste.
- **Status:** COMPLETED

## Pokrenuti alati:
- Get-DiskHealth.ps1
- Get-EventLogTriage.ps1
"@
    [System.IO.File]::WriteAllText((Join-Path $testReportsFolder "IZVESTAJ_DIJAGNOSTIKE.md"), $reportContent, [System.Text.Encoding]::UTF8)

    # -------------------------------------------------------------------------
    # TEST GRUPA 1: OFFLINE RAD (SCENARIO 2)
    # -------------------------------------------------------------------------
    Write-Host "`n[*] Test Grupa 1: Scenario 2 - Offline rad (Hub nedostupan)" -ForegroundColor Yellow

    # Pokrecemo push ka nepostojecem portu na localhost-u
    $offlineUrl = "http://127.0.0.1:59998"
    & $syncScript -Push -DeviceFolder $testDevFolder -HubUrl $offlineUrl

    # Provera da li je kreiran fajl u pending_sync/ radnog foldera
    # Napomena: skripta trazi pending_sync u root-u svog USB-a ili %TEMP%
    $pendingFiles = Get-ChildItem (Join-Path $scriptRoot "pending_sync\*.json") -ErrorAction SilentlyContinue
    Assert-True ($pendingFiles -and $pendingFiles.Count -gt 0) "Offline push kreira paket u pending_sync/"

    # Ciscenje testnog pending fajla
    if ($pendingFiles) {
        $pendingFiles | Where-Object { $_.Name -like "*$testGuid*" } | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # -------------------------------------------------------------------------
    # TEST GRUPA 2: PROVERA LIVE VEZE (AKO JE HUB DOSTUPAN)
    # -------------------------------------------------------------------------
    Write-Host "`n[*] Test Grupa 2: Scenario 1 - Pre-flight Pull i Post-flight Push" -ForegroundColor Yellow
    $isHubOnline = $false
    try {
        $health = Invoke-RestMethod -Uri "$HubUrl/api/health" -Method Get -TimeoutSec 2 -ErrorAction Stop
        if ($health.status -eq "ok") { $isHubOnline = $true }
    } catch {
        $isHubOnline = $false
    }

    if ($isHubOnline) {
        Write-Host "  [i] Pronadjen aktivan Servis Hub na $HubUrl. Pokrecem online testove..." -ForegroundColor Cyan

        # Pre-flight pull za novi uredjaj
        $pullNew = & $syncScript -Pull -DeviceTag "Novi_Uredjaj_$testGuid" -HubUrl $HubUrl
        Assert-Equal $pullNew.is_registered $false "Pre-flight pull za nepoznat uredjaj vraca is_registered: False"

        # Post-flight push za test uredjaj
        $pushRes = & $syncScript -Push -DeviceFolder $testDevFolder -HubUrl $HubUrl
        Assert-True ($pushRes.Success -and $pushRes.SentOnline) "Post-flight push uspesno poslat na Servis Hub"

        # Ponovni pull za registrovani uredjaj
        $pullReg = & $syncScript -Pull -DeviceTag $testDevTag -HubUrl $HubUrl
        Assert-Equal $pullReg.is_registered $true "Ponovni pull vraca is_registered: True"
        Assert-Equal $pullReg.serial_number "5CD$testGuid" "Pull vraca tacan serijski broj"

        # Flush pending
        & $syncScript -FlushPending -HubUrl $HubUrl
        Write-Host "  [PASS] FlushPending uspesno izvrsen." -ForegroundColor Green
        $script:testPassed++
    } else {
        Write-Host "  [SKIP] Servis Hub nije aktivan na $HubUrl (pokrenite hub_server.py za live testove)." -ForegroundColor DarkGray
    }

} finally {
    # Ciscenje privremenih test resursa
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "ZAVRSENI TESTOVI: $testPassed proslo, $testFailed palo." -ForegroundColor $(if ($testFailed -eq 0) { "Green" } else { "Red" })
Write-Host "==================================================================" -ForegroundColor Cyan

if ($testFailed -gt 0) { exit 1 } else { exit 0 }
