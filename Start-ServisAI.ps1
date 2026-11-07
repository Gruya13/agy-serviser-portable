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
    [switch]$Fallback,
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

$scriptDir = $PSScriptRoot.TrimEnd('\')
$binPath = Join-Path $scriptDir "bin\agy.exe"
$protectScript = Join-Path $scriptDir "scripts\Protect-USBIntegrity.ps1"
$deviceScript = Join-Path $scriptDir "scripts\Get-DeviceInfo.ps1"
$syncScript = Join-Path $scriptDir "scripts\Sync-ServiceHub.ps1"

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

$accountsDir = Join-Path $scriptDir "data\accounts"
$primaryDir  = Join-Path $accountsDir "primary"
$fallbackDir = Join-Path $accountsDir "fallback"

# Odabir izvornog naloga na USB-u
$selectedSourceDir = ""
if ($Fallback) {
    if (Test-Path $fallbackDir) {
        $selectedSourceDir = $fallbackDir
        Write-Host "[*] Izabran REZERVNI (fallback) servisni nalog na USB-u." -ForegroundColor Cyan
    } else {
        $selectedSourceDir = Join-Path $scriptDir "data"
        Write-Host "[*] Izabran podrazumevani prenosivi profil na USB medijumu." -ForegroundColor Green
    }
} elseif (Test-Path $primaryDir) {
    $primaryToken = Join-Path $primaryDir ".gemini\antigravity-cli\jetski-standalone-oauth-token"
    if (-not (Test-Path $primaryToken)) {
        $primaryToken = Join-Path $primaryDir ".gemini\antigravity-cli\antigravity-oauth-token"
    }

    if (Test-Path $primaryToken) {
        $selectedSourceDir = $primaryDir
        Write-Host "[*] Izabran PRIMARNI servisni nalog na USB medijumu." -ForegroundColor Green
    } elseif (Test-Path $fallbackDir) {
        $selectedSourceDir = $fallbackDir
        Write-Host "[!] Primarni nalog nije pronadjen. Automatski se bira REZERVNI servisni nalog..." -ForegroundColor Yellow
    } else {
        $selectedSourceDir = Join-Path $scriptDir "data"
        Write-Host "[*] Izabran podrazumevani profil na USB medijumu." -ForegroundColor Green
    }
} elseif (Test-Path $fallbackDir) {
    $selectedSourceDir = $fallbackDir
    Write-Host "[*] Izabran REZERVNI servisni nalog na USB-u." -ForegroundColor Cyan
} else {
    $selectedSourceDir = Join-Path $scriptDir "data"
    Write-Host "[*] Koristi se podrazumevani profil na USB medijumu." -ForegroundColor Green
}

$isUsingTemp = $false
$profileDir = ""

if ($isReadOnly -or $ForceTempProfile) {
    $isUsingTemp = $true
    $tempFolderName = "ServisAI_" + [guid]::NewGuid().ToString().Substring(0, 8)
    $profileDir = Join-Path $env:TEMP $tempFolderName
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    
    # Preslikavanje naloga sa USB-a u privremeni profil radi nesmetanog rada
    if ($selectedSourceDir -and (Test-Path $selectedSourceDir)) {
        Copy-Item -Path "$selectedSourceDir\*" -Destination $profileDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[*] USB je Read-Only. Aktiviran prenosivi privremeni profil sa tokenima: $profileDir" -ForegroundColor Magenta
} else {
    $profileDir = $selectedSourceDir
    Write-Host "[*] Aktivna trajna sesija sa USB medijuma: $profileDir" -ForegroundColor Green
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

        # Pre-flight sinhronizacija i provera servisne istorije na centralnom Servis Hub-u
        if (Test-Path $syncScript) {
            Write-Host "[*] Provera servisne istorije na centralnom Servis Hub-u..." -ForegroundColor Yellow
            try {
                $hubHistory = & $syncScript -Pull -DeviceTag $device.DeviceTag -SerialNumber $device.SerialNumber -DeviceFolder $device.DeviceFolder
                if ($hubHistory -and $hubHistory.is_registered) {
                    $env:SERVIS_HUB_HISTORY_AVAILABLE = "true"
                    Write-Host "[OK] Servisna istorija uspesno ucitana u radni prostor agenta." -ForegroundColor Green
                } else {
                    Write-Host "[*] Uredjaj se prvi put evidentira. Pokrecem automatsku Pre-flight registraciju na Hub-u..." -ForegroundColor Cyan
                    & $syncScript -Register -DeviceTag $device.DeviceTag -SerialNumber $device.SerialNumber -DeviceFolder $device.DeviceFolder -Status "U_DIJAGNOSTICI"
                    $env:SERVIS_HUB_HISTORY_AVAILABLE = "false"
                }
            } catch {
                Write-Host "[!] Upozorenje pri komunikaciji sa Servis Hub-om: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

# 6. Postavljanje izolacije okruzenja i uskladjivanje sa Windows OS
$originalUserProfile   = $env:USERPROFILE
$originalHome          = $env:HOME
$originalHomeDrive     = $env:HOMEDRIVE
$originalHomePath      = $env:HOMEPATH
$originalAppData       = $env:APPDATA
$originalLocalAppData  = $env:LOCALAPPDATA
$originalSSHClient     = $env:SSH_CLIENT
$originalSSHConnection = $env:SSH_CONNECTION
$originalSSHTTY        = $env:SSH_TTY

$env:USERPROFILE = $profileDir
$env:HOME        = $profileDir

# Uskladjivanje HOMEDRIVE i HOMEPATH za Go i Win32 runtime
if ($profileDir -match '^([A-Za-z]:)(.*)$') {
    $env:HOMEDRIVE = $matches[1]
    $env:HOMEPATH  = $matches[2]
}

# Postavljanje APPDATA i LOCALAPPDATA na profil (sa kreiranjem podfoldera)
$roamingDir = Join-Path $profileDir "AppData\Roaming"
$localDir   = Join-Path $profileDir "AppData\Local"
if (-not (Test-Path $roamingDir)) { New-Item -ItemType Directory -Path $roamingDir -Force | Out-Null }
if (-not (Test-Path $localDir))   { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
$env:APPDATA      = $roamingDir
$env:LOCALAPPDATA = $localDir

# Forsiranje headless/remote autorizacije (zaobilazi lokalni keyring i forsira file token storage)
$env:SSH_CLIENT     = "127.0.0.1 12345 22"
$env:SSH_CONNECTION = "127.0.0.1 12345 127.0.0.1 22"
$env:SSH_TTY        = "/dev/pts/0"

# SMART TOKEN BRIDGE: Ako agy.exe na Windows-u poziva Win32 API GetUserProfileDirectoryW,
# osiguravamo da privremeno vidi tokene i na lokalnom klijentskom profilu tokom trajanja sesije
$clientUserProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$injectedClientTokens = $false
$clientGeminiCliDir = ""

if ($clientUserProfile -and (Test-Path $clientUserProfile)) {
    $clientGeminiCliDir = Join-Path $clientUserProfile ".gemini\antigravity-cli"
    $clientTokenFile = Join-Path $clientGeminiCliDir "jetski-standalone-oauth-token"
    
    if (-not (Test-Path $clientTokenFile)) {
        try {
            $srcTokenDir = Join-Path $profileDir ".gemini\antigravity-cli"
            if (Test-Path $srcTokenDir) {
                if (-not (Test-Path $clientGeminiCliDir)) {
                    New-Item -ItemType Directory -Path $clientGeminiCliDir -Force | Out-Null
                }
                Copy-Item -Path "$srcTokenDir\*" -Destination $clientGeminiCliDir -Recurse -Force -ErrorAction Stop
                $injectedClientTokens = $true
                Write-Host "[*] Uspešno postavljen privremeni most akreditiva za lokalni Windows profil." -ForegroundColor DarkCyan
            }
        } catch {
            Write-Host "[!] Napomena pri postavljanju mosta akreditiva: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }
}

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

    # Upravljanje odjavom: odjava se radi SAMO ako je eksplicitno zatrazen -Logout
    if ($Logout) {
        try {
            & $binPath "/logout" 2>$null | Out-Null
            Write-Host "[OK] Izvrsena odjava Google naloga (/logout)." -ForegroundColor Green
        } catch {}
    } else {
        Write-Host "[OK] Prijava ostaje sacuvana na USB-u za brzi rad na sledecim masinama." -ForegroundColor Green
    }

    # Bezbedno ciscenje privremenog mosta akreditiva sa klijentskog racunara (Zero-trace)
    if ($injectedClientTokens -and $clientGeminiCliDir -and (Test-Path $clientGeminiCliDir)) {
        try {
            # Ako je agy.exe osvezio tokene u klijentskom profilu, vrati ih nazad na USB
            $usbTokenDir = Join-Path $profileDir ".gemini\antigravity-cli"
            if (Test-Path $usbTokenDir) {
                Copy-Item -Path "$clientGeminiCliDir\*" -Destination $usbTokenDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Remove-Item -Path $clientGeminiCliDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Privremeni most akreditiva bezbedno uklonjen sa klijentskog racunara (Zero-trace)." -ForegroundColor Green
        } catch {
            Write-Host "[!] Upozorenje pri ciscenju mosta akreditiva: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Ako je koriscen privremeni profil, brisanje sa klijentskog racunara
    if ($isUsingTemp -and (Test-Path $profileDir)) {
        try {
            Remove-Item -Path $profileDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Privremeni radni profil obrisan sa klijentskog racunara." -ForegroundColor Green
        } catch {
            Write-Host "[!] Upozorenje: Neki privremeni fajlovi nisu mogli biti obrisani: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Vracanje originalnih varijabli okruzenja
    $env:USERPROFILE   = $originalUserProfile
    $env:HOME          = $originalHome
    $env:HOMEDRIVE     = $originalHomeDrive
    $env:HOMEPATH      = $originalHomePath
    $env:APPDATA       = $originalAppData
    $env:LOCALAPPDATA  = $originalLocalAppData
    $env:SSH_CLIENT     = $originalSSHClient
    $env:SSH_CONNECTION = $originalSSHConnection
    $env:SSH_TTY        = $originalSSHTTY

    # Sinhronizacija servisnog kartona i sesije na Servis Hub
    if ($device -and (Test-Path $syncScript)) {
        Write-Host "[*] Sinhronizacija servisnog kartona i sesije na Servis Hub..." -ForegroundColor Yellow
        try {
            & $syncScript -Push -DeviceTag $device.DeviceTag -SerialNumber $device.SerialNumber -DeviceFolder $device.DeviceFolder
        } catch {
            Write-Host "[!] Upozorenje pri slanju podataka na Servis Hub: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

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
