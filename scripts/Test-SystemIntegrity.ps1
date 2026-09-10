<#
.SYNOPSIS
    Provera integriteta sistemskih datoteka i komponentnog skladista (SFC / DISM).
.DESCRIPTION
    Bezbedna (non-destructive) provera sistemskih datoteka koriscenjem SFC /VERIFYONLY
    i DISM CheckHealth / ScanHealth. Ne vrsi izmene na disku bez parametra -Repair.
#>

[CmdletBinding()]
param (
    [switch]$FullScan,
    [switch]$Repair
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "         PROVERA INTEGRITETA SISTEMA (SFC / DISM REZIM)           " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. DISM CheckHealth (Trenutna provera da li je sistem vec markiran kao ostecen)
Write-Host "[*] 1. DISM CheckHealth (Provera zastavica ostecenja komponentnog skladista)..." -ForegroundColor Yellow
$dismCheck = dism.exe /Online /Cleanup-Image /CheckHealth 2>&1
$dismCheck | ForEach-Object {
    if ($_ -match "The component store is repairable|komponentno skladiste se moze popraviti") {
        Write-Host "    [!] UPOZORENJE: Komponentno skladiste je OSTECENO ali se moze popraviti!" -ForegroundColor Yellow
    } elseif ($_ -match "No component store corruption detected|Nije otkriveno ostecenje") {
        Write-Host "    [OK] Nije otkriveno prethodno ostecenje komponentnog skladista." -ForegroundColor Green
    } elseif ($_ -match "The component store is not repairable") {
        Write-Host "    [X] KRITICNO: Komponentno skladiste ima NEPOPRAVLJIVO ostecenje!" -ForegroundColor Red
    }
}

# 2. DISM ScanHealth (Detaljno skeniranje ako je zatrazeno)
if ($FullScan -or $Repair) {
    Write-Host "`n[*] 2. DISM ScanHealth (Kompletno skeniranje komponenti, molimo sacekajte)..." -ForegroundColor Yellow
    $dismScan = dism.exe /Online /Cleanup-Image /ScanHealth 2>&1
    $dismScan | ForEach-Object {
        if ($_ -match "Error|Greska") {
            Write-Host "    $_" -ForegroundColor Red
        } elseif ($_ -match "completed|zavrseno") {
            Write-Host "    $_" -ForegroundColor Green
        }
    }
}

# 3. SFC Provera sistemskih datoteka
if ($Repair) {
    Write-Host "`n[*] 3. SFC /SCANNOW (Izvrsava se automatska popravka ostecenih datoteka)..." -ForegroundColor Yellow
    sfc.exe /scannow
} else {
    Write-Host "`n[*] 3. SFC /VERIFYONLY (Bezbedno skeniranje integriteta bez modifikacije fajlova)..." -ForegroundColor Yellow
    $sfcOut = sfc.exe /verifyonly 2>&1
    $sfcOut | ForEach-Object {
        if ($_ -match "found integrity violations|otkrio je narusavanja integriteta") {
            Write-Host "    [!] UPOZORENJE: SFC je pronasao ostecene sistemske datoteke!" -ForegroundColor Red
            Write-Host "        Preporuka: Pokrenuti popravku putem DISM /RestoreHealth i SFC /scannow." -ForegroundColor Yellow
        } elseif ($_ -match "did not find any integrity violations|nije pronasao nikakva narusavanja") {
            Write-Host "    [OK] SFC nije pronasao nikakva narusavanja integriteta sistema." -ForegroundColor Green
        } else {
            Write-Host "    $_" -ForegroundColor Gray
        }
    }
}

Write-Host "==================================================================" -ForegroundColor Cyan
