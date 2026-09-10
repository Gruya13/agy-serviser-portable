<#
.SYNOPSIS
    Glavni orkestrator za Antigravity CLI Prenosivi Servisni Asistent.
.DESCRIPTION
    Ova skripta proverava internet vezu, aktivira USB samozastitu,
    automatski identifikuje klijentski racunar po serijskom broju,
    kreira digitalni servisni karton (devices\<DeviceTag>),
    odvaja sesije/cetove po masinama, omogucava nastavak razgovora za isti racunar,
    i zadrzava trajnu deljenu prijavu na USB medijumu bez ponovne autorizacije.
#>

[CmdletBinding()]
param (
    [switch]$ForceTempProfile,
    [switch]$Logout,
    [string]$Model
)

$Host.UI.RawUI.WindowTitle = "Servis AI Asistent - Antigravity CLI Portable"
Clear-Host

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "         ANTIGRAVITY CLI PORTABLE - SERVISNI ASISTENT             " -ForegroundColor Yellow
Write-Host "           Google AI Pro Tehnologija za Servisnu Dijagnostiku     " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$binPath = Join-Path $scriptDir "bin\agy.exe"
$protectScript = Join-Path $scriptDir "scripts\Protect-USBIntegrity.ps1"
$deviceScript = Join-Path $scriptDir "scripts\Get-DeviceInfo.ps1"

# 1. Provera postojanja agy.exe
if (-not (Test-Path $binPath)) {
    Write-Host "[X] GRESKA: Nije pronadjen fajl 'bin\agy.exe'!" -ForegroundColor Red
    Write-Host "    Molimo vas da preuzmete Antigravity CLI za Windows i smestite ga u:" -ForegroundColor Yellow
    Write-Host "    $binPath" -ForegroundColor White
    Write-Host "    Za uputstvo pogledajte: $scriptDir\bin\README_BIN.md" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Pritisnite Enter za izlaz..."
    exit 1
}

# 2. USB Samozastita i Imunizacija (Pre-run provera)
if (Test-Path $protectScript) {
    Write-Host "[*] Pokrecem USB samozastitu i proveru integriteta medijuma..." -ForegroundColor Yellow
    & $protectScript -Vaccinate -AutoClean
    Write-Host ""
}

# 3. Provera internet konekcije
Write-Host "[*] Provera internet veze sa servisima..." -NoNewline
$hasInternet = $false
try {
    $request = [System.Net.WebRequest]::Create("https://www.google.com")
    $request.Timeout = 4000
    $response = $request.GetResponse()
    $response.Close()
    $hasInternet = $true
} catch {
    $hasInternet = $false
}

if ($hasInternet) {
    Write-Host " [OK]" -ForegroundColor Green
} else {
    Write-Host " [UPOZORENJE]" -ForegroundColor Yellow
    Write-Host "[!] Nije moguce uspostaviti vezu sa internetom." -ForegroundColor Yellow
    Write-Host "    Google AI Pro model zahteva aktivnu vezu za komunikaciju." -ForegroundColor Gray
    $izbor = Read-Host "Zelite li da nastavite bez obzira na ovo? (d/n)"
    if ($izbor -ne 'd' -and $izbor -ne 'D') {
        exit 1
    }
}

# 4. Detekcija Write-Protect statusa USB-a i odredjivanje profila
$isReadOnly = $false
$testFile = Join-Path $scriptDir (".write_test_" + [guid]::NewGuid().ToString().Substring(0, 6))

try {
    [System.IO.File]::WriteAllText($testFile, "test")
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    }
} catch {
    $isReadOnly = $true
}

$isUsingTemp = $false
$profileDir = ""

if ($isReadOnly -or $ForceTempProfile) {
    $isUsingTemp = $true
    $tempFolderName = "ServisAI_" + [guid]::NewGuid().ToString().Substring(0, 8)
    $profileDir = Join-Path $env:TEMP $tempFolderName
    Write-Host "[*] Koristi se izolovani privremeni profil: $profileDir" -ForegroundColor Magenta
} else {
    $profileDir = Join-Path $scriptDir "data"
    Write-Host "[*] Koristi se prenosivi profil na USB medijumu (Trajna sesija): $profileDir" -ForegroundColor Green
}

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# 5. Identifikacija klijentskog racunara i servisni karton (devices\<DeviceTag>)
$devicesBaseDir = if ($isUsingTemp) { Join-Path $profileDir "devices" } else { Join-Path $scriptDir "devices" }
if (-not (Test-Path $devicesBaseDir)) { New-Item -ItemType Directory -Path $devicesBaseDir -Force | Out-Null }

$device = $null
$workDir = $scriptDir

if (Test-Path $deviceScript) {
    Write-Host "`n[*] Ocitavanje identifikacije i hardvera klijentskog racunara..." -ForegroundColor Yellow
    $device = & $deviceScript -TargetDevicesDir $devicesBaseDir
    if ($device) {
        $workDir = $device.DeviceFolder
        Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "IDENTIFIKOVAN KLIJENTSKI RACUNAR:" -ForegroundColor Yellow
        Write-Host "  - Uredjaj:       $($device.Manufacturer) $($device.Model)" -ForegroundColor White
        Write-Host "  - Serijski broj: $($device.SerialNumber)" -ForegroundColor Green
        Write-Host "  - Hardver:       $($device.CPU) | $($device.RAMGB) GB RAM" -ForegroundColor Gray
        Write-Host "  - Servisni folder: $($device.DeviceFolder)" -ForegroundColor DarkGray
        Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan

        # Sinhronizacija AGENTS.md, skripti i vestina u radni folder uredjaja
        $deviceAgentsMd = Join-Path $workDir "AGENTS.md"
        Copy-Item (Join-Path $scriptDir "AGENTS.md") $deviceAgentsMd -Force -ErrorAction SilentlyContinue

        $deviceSkills = Join-Path $workDir ".agents"
        if (-not (Test-Path $deviceSkills)) {
            Copy-Item (Join-Path $scriptDir ".agents") $deviceSkills -Recurse -Force -ErrorAction SilentlyContinue
        }
        $deviceScripts = Join-Path $workDir "scripts"
        if (-not (Test-Path $deviceScripts)) {
            Copy-Item (Join-Path $scriptDir "scripts") $deviceScripts -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 6. Postavljanje izolacije okruzenja
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalSSHClient = $env:SSH_CLIENT
$originalSSHTTY = $env:SSH_TTY

$env:USERPROFILE = $profileDir
$env:HOME = $profileDir

# Forsiranje headless/remote autorizacije ako nismo ulogovani
$env:SSH_CLIENT = "127.0.0.1 12345 22"
$env:SSH_TTY = "/dev/pts/0"

Write-Host "[*] Headless OAuth zastita aktivna (autorizacija se vrsi preko telefona)." -ForegroundColor Cyan

# 7. Priprema argumenata za Antigravity CLI i ponuda nastavka sesije
$cliArgs = @()
if ($Model) {
    $cliArgs += "--model"
    $cliArgs += $Model
}

# Ako je racunar vec bio servisiran, ponuditi nastavak prethodnog razgovora za taj racunar
if ($device -and $device.IsExistingDevice) {
    Write-Host "`n[!] Ovaj racunar je vec evidentiran u servisnoj bazi!" -ForegroundColor Cyan
    Write-Host "    [1] Nastavi prethodni razgovor/sesiju za ovaj racunar (agy -c)" -ForegroundColor Green
    Write-Host "    [2] Zapocni novu dijagnosticku sesiju za ovaj racunar" -ForegroundColor White
    $izborSesije = Read-Host "Izaberite opciju (1/2, podrazumevano 1)"
    if ($izborSesije -ne '2') {
        $cliArgs += "-c"
        Write-Host "[*] Ucitavam prethodni razgovor za uredjaj $($device.DeviceTag)..." -ForegroundColor Green
    } else {
        Write-Host "[*] Otvaram novu sesiju za uredjaj $($device.DeviceTag)..." -ForegroundColor Yellow
    }
}

Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

# 8. Pokretanje sesije u radnom prostoru uredjaja
try {
    Set-Location $workDir
    Write-Host "[*] Pokrecem Antigravity CLI sesiju za ovaj uredjaj... (izlaz: /exit ili Ctrl+D)" -ForegroundColor Yellow
    Write-Host ""
    & $binPath $cliArgs
} finally {
    Set-Location $scriptDir
    Write-Host ""
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[*] Zavrsavanje sesije i post-sesijsko ciscenje..." -ForegroundColor Cyan

    # Upravljanje odjavom: odjava se radi ako je koriscen TEMP profil ili ako je eksplicitno zatrazen -Logout
    if ($isUsingTemp -or $Logout) {
        try {
            & $binPath "/logout" 2>$null | Out-Null
            Write-Host "[OK] Izvrsena odjava Google naloga (/logout)." -ForegroundColor Green
        } catch {}
    } else {
        Write-Host "[OK] Prijava ostaje sacuvana na USB-u za brzi rad na sledecim masinama." -ForegroundColor Green
    }

    # Ako je koriscen privremeni profil, brisanje sa klijentskog racunara
    if ($isUsingTemp -and (Test-Path $profileDir)) {
        try {
            Remove-Item -Path $profileDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Privremeni radni profil obrisan sa klijentskog racunara (Nema tragova)." -ForegroundColor Green
        } catch {
            Write-Host "[!] Upozorenje: Neki privremeni fajlovi nisu mogli biti obrisani: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Vracanje originalnih varijabli okruzenja
    $env:USERPROFILE = $originalUserProfile
    $env:HOME = $originalHome
    $env:SSH_CLIENT = $originalSSHClient
    $env:SSH_TTY = $originalSSHTTY

    # Zavrsno samociscenje USB-a (neutralisanje malvera koji je klijent mozda pokusao da upise)
    if (Test-Path $protectScript) {
        Write-Host "[*] Pokrecem zavrsno samociscenje USB medijuma..." -ForegroundColor Yellow
        & $protectScript -AutoClean
    }

    Write-Host "[OK] Servisna sesija je bezbedno zavrsena." -ForegroundColor Green
}
