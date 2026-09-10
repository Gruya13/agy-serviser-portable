<#
.SYNOPSIS
    Glavni orkestrator za Antigravity CLI Prenosivi Servisni Asistent.
.DESCRIPTION
    Ova skripta proverava internet vezu, detektuje radni medijum (Write-Protect podrška),
    izoluje korisnički profil, pokreće Antigravity CLI u headless režimu
    i osigurava automatsku odjavu i čišćenje privremenih tragova sa klijentske mašine.
#>

[CmdletBinding()]
param (
    [switch]$ForceTempProfile,
    [string]$Model
)

$Host.UI.RawUI.WindowTitle = "Servis AI Asistent - Antigravity CLI Portable"
Clear-Host

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "         ANTIGRAVITY CLI PORTABLE - SERVISNI ASISTENT             " -ForegroundColor Yellow
Write-Host "           Google AI Pro Tehnologija za Servisnu Dijagnostiku     " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Provera postojanja agy.exe
$scriptDir = $PSScriptRoot
$binPath = Join-Path $scriptDir "bin\agy.exe"

if (-not (Test-Path $binPath)) {
    Write-Host "[X] GRESKA: Nije pronadjen fajl 'bin\agy.exe'!" -ForegroundColor Red
    Write-Host "    Molimo vas da preuzmete Antigravity CLI za Windows i smestite ga u:" -ForegroundColor Yellow
    Write-Host "    $binPath" -ForegroundColor White
    Write-Host "    Za uputstvo pogledajte: $scriptDir\bin\README_BIN.md" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Pritisnite Enter za izlaz..."
    exit 1
}

# 2. Provera internet konekcije
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

# 3. Detekcija Write-Protect statusa USB-a i odredjivanje profila
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
    Write-Host "[*] Detektovan Write-Protect USB medijum ili je ukljucen privremeni rezim." -ForegroundColor Magenta
    Write-Host "[*] Koristi se izolovani privremeni profil: $profileDir" -ForegroundColor Gray
} else {
    $profileDir = Join-Path $scriptDir "data"
    Write-Host "[*] Koristi se prenosivi profil na USB medijumu: $profileDir" -ForegroundColor Green
}

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# 4. Postavljanje izolacije okruzenja
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalSSHClient = $env:SSH_CLIENT
$originalSSHTTY = $env:SSH_TTY

$env:USERPROFILE = $profileDir
$env:HOME = $profileDir

# Forsiranje headless/remote autorizacije (sprecava pokretanje klijentskog browsera)
$env:SSH_CLIENT = "127.0.0.1 12345 22"
$env:SSH_TTY = "/dev/pts/0"

Write-Host "[*] Headless OAuth zastita aktivna (autorizacija se vrsi preko telefona)." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

# 5. Priprema argumenata za Antigravity CLI
$cliArgs = @()
if ($Model) {
    $cliArgs += "--model"
    $cliArgs += $Model
}

# 6. Pokretanje sesije
try {
    Set-Location $scriptDir
    Write-Host "[*] Pokrecem Antigravity CLI sesiju... (za izlaz unesite /exit ili Ctrl+D)" -ForegroundColor Yellow
    Write-Host ""
    & $binPath $cliArgs
} finally {
    Write-Host ""
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[*] Zavrsavanje sesije i pokretanje bezbednosnog ciscenja..." -ForegroundColor Cyan

    # Odjava naloga preko CLI
    try {
        & $binPath "/logout" 2>$null | Out-Null
        Write-Host "[OK] Uspesno izvrsena odjava Google naloga (/logout)." -ForegroundColor Green
    } catch {
        Write-Host "[!] Odjava preko CLI nije uspela ili je sesija vec prekinuta." -ForegroundColor Yellow
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

    Write-Host "[OK] Okruzenje vraceno u pocetno stanje." -ForegroundColor Green
}
