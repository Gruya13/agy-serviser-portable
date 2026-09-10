<#
.SYNOPSIS
    Automatska zastita, imunizacija i samociscenje USB medijuma od virusa i malvera.
.DESCRIPTION
    Skenira USB na postojanje tipicnih USB crva (preacice .lnk, skriveni .exe, .vbs skripte, autorun.inf).
    Vrsi proveru integriteta (SHA-256) kljucnih fajlova i automatski vakcinise koren medijuma.
#>

[CmdletBinding()]
param (
    [switch]$AutoClean,
    [switch]$Vaccinate,
    [switch]$GenerateChecksums
)

$ErrorActionPreference = "SilentlyContinue"
$scriptDir = Split-Path $PSScriptRoot -Parent
$checksumFile = Join-Path $scriptDir "config\checksums.json"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "          USB SAMOZASTITA I KONTROLA INTEGRITETA MEDIJUMA         " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Vakcinacija USB-a (Imunizacija protiv Autorun crva)
if ($Vaccinate) {
    Write-Host "[*] Primena imunizacije korena USB medijuma..." -ForegroundColor Yellow
    $autorunPath = Join-Path $scriptDir "autorun.inf"
    
    if (Test-Path $autorunPath) {
        $item = Get-Item $autorunPath -Force
        if (-not $item.PSIsContainer) {
            # Ako je autorun.inf fajl a ne folder, moguce da je maliciozan!
            Write-Host "  [!] Uklanjam postojeci autorun.inf fajl..." -ForegroundColor Yellow
            Remove-Item $autorunPath -Force
        }
    }

    if (-not (Test-Path $autorunPath)) {
        try {
            $newDir = New-Item -ItemType Directory -Path $autorunPath -Force
            # Postavljanje ReadOnly, Hidden i System atributa
            $newDir.Attributes = [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
            Write-Host "  [OK] Imunizacija uspesno postavljena (autorun.inf folder zakljucan)." -ForegroundColor Green
        } catch {
            Write-Host "  [!] Nije moguce postaviti imunizaciju: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] USB je vec imunizovan (zasticen autorun.inf folder)." -ForegroundColor Green
    }
}

# 2. Skeniranje sumnjivih fajlova i USB crva
Write-Host "`n[*] Skeniranje USB-a na sumnjive maliciozne datoteke..." -ForegroundColor Yellow
$suspiciousExtensions = @("*.lnk", "*.vbs", "*.js", "*.scr", "*.pif", "*.hta", "*.wsf")
$foundThreats = @()

# Dozvoljene skripte unutar naseg projekta
$whitelistedFiles = @("Start-ServisAI.bat", "autorun.inf")

foreach ($ext in $suspiciousExtensions) {
    $matches = Get-ChildItem -Path $scriptDir -Filter $ext -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($m in $matches) {
        # Ako je .lnk ili .vbs na USB-u, 99.9% je USB Shortcut virus sa klijenta
        $foundThreats += $m
    }
}

# Provera sumnjivih .exe fajlova van bin\ foldera
$strayExe = Get-ChildItem -Path $scriptDir -Filter "*.exe" -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.DirectoryName -ne (Join-Path $scriptDir "bin") -and $_.DirectoryName -ne (Join-Path $scriptDir "bin\tools")
}
if ($strayExe) {
    $foundThreats += $strayExe
}

# Provera skrivenih objekata u korenu koji ne pripadaju standardnoj strukturi
$hiddenInRoot = Get-ChildItem -Path $scriptDir -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Attributes -match "Hidden" -and $_.Name -notin @(".git", ".agents", "autorun.inf", "data")
}
if ($hiddenInRoot) {
    $foundThreats += $hiddenInRoot
}

if ($foundThreats.Count -gt 0) {
    Write-Host "  [!] PRONADJENE SU SUMNJIVE PRETNJE NA USB-u ($($foundThreats.Count) stavki):" -ForegroundColor Red
    foreach ($threat in $foundThreats) {
        Write-Host "      - $($threat.FullName) [Atributi: $($threat.Attributes)]" -ForegroundColor Red
        if ($AutoClean) {
            try {
                # Skidanje atributa pre brisanja
                $threat.Attributes = [System.IO.FileAttributes]::Normal
                Remove-Item $threat.FullName -Force -Recurse -ErrorAction Stop
                Write-Host "        [OCISCENO] Fajl je automatski uklonjen!" -ForegroundColor Green
            } catch {
                Write-Host "        [GRESKA] Neuspesno brisanje: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    if (-not $AutoClean) {
        Write-Host "  [!] Pokrenite skriptu sa -AutoClean parametrom radi automatskog uklanjanja." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [OK] Nisu pronadjeni poznati obrasci USB crva i preacica." -ForegroundColor Green
}

# 3. Generisanje ili provera integriteta fajlova (SHA256 Checksums)
if ($GenerateChecksums) {
    Write-Host "`n[*] Generisanje kontrolnih heseva (SHA256) za sistemske fajlove..." -ForegroundColor Yellow
    $checksumData = @{}
    
    $filesToHash = @()
    if (Test-Path (Join-Path $scriptDir "bin\agy.exe")) {
        $filesToHash += (Join-Path $scriptDir "bin\agy.exe")
    }
    $filesToHash += Get-ChildItem -Path (Join-Path $scriptDir "scripts") -Filter "*.ps1" | ForEach-Object { $_.FullName }
    $filesToHash += (Join-Path $scriptDir "Start-ServisAI.bat")
    $filesToHash += (Join-Path $scriptDir "Start-ServisAI.ps1")
    $filesToHash += (Join-Path $scriptDir "AGENTS.md")

    foreach ($file in $filesToHash) {
        if (Test-Path $file) {
            $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash
            $relPath = $file.Replace($scriptDir, "").TrimStart("\/")
            $checksumData[$relPath] = $hash
        }
    }

    $json = $checksumData | ConvertTo-Json -Depth 2
    [System.IO.File]::WriteAllText($checksumFile, $json)
    Write-Host "  [OK] Heš lista kreirana u $checksumFile ($($checksumData.Count) fajlova)." -ForegroundColor Green
} elseif (Test-Path $checksumFile) {
    Write-Host "`n[*] Verifikacija integriteta sistemskih alata (Tamper Detection)..." -ForegroundColor Yellow
    try {
        $savedHashes = Get-Content $checksumFile -Raw | ConvertFrom-Json
        $tampered = $false

        foreach ($prop in $savedHashes.PSObject.Properties) {
            $relPath = $prop.Name
            $expectedHash = $prop.Value
            $fullPath = Join-Path $scriptDir $relPath

            if (Test-Path $fullPath) {
                $actualHash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash
                if ($actualHash -ne $expectedHash) {
                    $tampered = $true
                    Write-Host "  [X] UPOZORENJE O MODIFIKACIJI: $relPath ima izmenjen heš!" -ForegroundColor Red
                    Write-Host "      Ocekivano: $expectedHash" -ForegroundColor DarkGray
                    Write-Host "      Trenutno:  $actualHash" -ForegroundColor Red
                }
            } else {
                Write-Host "  [!] Nedostaje fajl: $relPath" -ForegroundColor Yellow
            }
        }

        if (-not $tampered) {
            Write-Host "  [OK] Integritet svih kljucnih fajlova je sacuvan (Nema promena ni infekcija)." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Nije moguce proveriti heseve: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "==================================================================" -ForegroundColor Cyan
