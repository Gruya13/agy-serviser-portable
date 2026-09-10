<#
.SYNOPSIS
    Glavni orkestrator za Antigravity CLI Prenosivi Servisni Asistent.
.DESCRIPTION
    Ova skripta proverava internet vezu, aktivira USB samozastitu,
    automatski identifikuje klijentski racunar po serijskom broju,
    kreira digitalni servisni karton (devices\<DeviceTag>),
    odvaja radne prostore po masinama i zadrzava trajnu deljenu prijavu na USB medijumu.
#>

[CmdletBinding()]
param (
    [switch]$ForceTempProfile,
    [switch]$Logout,
    [string]$Model
)

$ErrorActionPreference = "Continue"

# 0. Konfiguracija UTF-8 i bafera konzole
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    
    if ($Host.UI.RawUI) {
        $raw = $Host.UI.RawUI
        if ($raw.BufferSize.Height -lt 9000) {
            $raw.BufferSize = New-Object System.Management.Automation.Host.Size($raw.BufferSize.Width, 9000)
        }
    }
} catch {}

$env:TERM = "xterm-256color"
$env:PAGER = "cat"

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
    return
}

# 2. USB Samozastita i Imunizacija (Pre-run provera)
if (Test-Path $protectScript) {
    Write-Host "[*] Pokrecem USB samozastitu i proveru integriteta medijuma..." -ForegroundColor Yellow
    try {
        & $protectScript -Vaccinate -AutoClean
    } catch {
        Write-Host "[!] Upozorenje tokom samozastite: $($_.Exception.Message)" -ForegroundColor Yellow
    }
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
    $izbor = Read-Host "Zelite li da nastavite bez obzira na ovo? (d/n, podrazumevano d)"
    if ($izbor -eq 'n' -or $izbor -eq 'N') {
        return
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
if (Test-Path $deviceScript) {
    Write-Host "[*] Ocitavanje hardvera i serijskog broja klijentskog racunara..." -ForegroundColor Yellow
    try {
        $device = & $deviceScript -TargetDevicesDir $devicesBaseDir
    } catch {
        Write-Host "[!] Upozorenje pri ocitavanju uredjaja: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if ($device) {
        Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "IDENTIFIKOVAN KLIJENTSKI RACUNAR:" -ForegroundColor Yellow
        Write-Host "  - Uredjaj:       $($device.Manufacturer) $($device.Model)" -ForegroundColor White
        Write-Host "  - Serijski broj: $($device.SerialNumber)" -ForegroundColor Green
        Write-Host "  - Hardver:       $($device.CPU) | $($device.RAMGB) GB RAM" -ForegroundColor Gray
        Write-Host "  - Karton:        $($device.DeviceFolder)" -ForegroundColor DarkGray
        Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan

        # Postavljanje promenljivih okruzenja za agenta
        $env:CURRENT_DEVICE_DIR = $device.DeviceFolder
        $env:CURRENT_DEVICE_TAG = $device.DeviceTag
    }
}

# 6. Postavljanje izolacije okruzenja
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalSSHClient = $env:SSH_CLIENT
$originalSSHTTY = $env:SSH_TTY

$env:USERPROFILE = $profileDir
$env:HOME = $profileDir

# Forsiranje headless/remote autorizacije
$env:SSH_CLIENT = "127.0.0.1 12345 22"
$env:SSH_TTY = "/dev/pts/0"

Write-Host "[*] Headless OAuth zastita aktivna (autorizacija se vrsi preko telefona)." -ForegroundColor Cyan

# 7. Priprema argumenata za Antigravity CLI
$cliArgs = @()
if ($Model) {
    $cliArgs += "--model"
    $cliArgs += $Model
}

# Ako uredjaj ima svoj folder, dodajemo ga u radni prostor agenta
if ($device -and (Test-Path $device.DeviceFolder)) {
    $cliArgs += "--add-dir"
    $cliArgs += $device.DeviceFolder
}

# Provera da li postoji sacuvana prethodna sesija za nastavak
$hasPreviousSession = $false
if ($device) {
    $sessionMarker = Join-Path $device.DeviceFolder "sessions\.has_session"
    if (Test-Path $sessionMarker) {
        $hasPreviousSession = $true
    }
}

if ($hasPreviousSession) {
    Write-Host "`n[!] Pronadjena je prethodna servisna sesija za ovaj racunar!" -ForegroundColor Cyan
    Write-Host "    [1] Nastavi prethodni razgovor za ovaj racunar (agy -c)" -ForegroundColor Green
    Write-Host "    [2] Zapocni novu dijagnosticku sesiju za ovaj racunar (Podrazumevano)" -ForegroundColor White
    $izborSesije = Read-Host "Izaberite opciju (1/2, podrazumevano 2)"
    if ($izborSesije -eq '1') {
        $cliArgs += "-c"
        Write-Host "[*] Ucitavam prethodni razgovor..." -ForegroundColor Green
    } else {
        Write-Host "[*] Otvaram novu sesiju..." -ForegroundColor Yellow
    }
}

Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

# 8. Pokretanje sesije
try {
    Set-Location $scriptDir
    Write-Host "[*] Pokrecem Antigravity CLI sesiju... (za izlaz unesite /exit ili Ctrl+D)" -ForegroundColor Yellow
    Write-Host ""
    
    & $binPath $cliArgs

    # Zabelezi da je sesija uspesno pokrenuta za ovaj uredjaj
    if ($device -and (Test-Path $device.DeviceFolder)) {
        $sessionMarker = Join-Path $device.DeviceFolder "sessions\.has_session"
        [System.IO.File]::WriteAllText($sessionMarker, (Get-Date).ToString("o"))
    }
} catch {
    Write-Host "`n[X] Doslo je do greske pri pokretanju Antigravity CLI: $($_.Exception.Message)" -ForegroundColor Red
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
        try {
            & $protectScript -AutoClean
        } catch {}
    }

    Write-Host "[OK] Servisna sesija je bezbedno zavrsena." -ForegroundColor Green
    Write-Host ""
    Read-Host "Pritisnite Enter za zatvaranje prozora..."
}
