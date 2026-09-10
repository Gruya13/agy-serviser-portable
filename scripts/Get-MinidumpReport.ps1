<#
.SYNOPSIS
    Pregled i izvestaj o BSOD (Blue Screen of Death) minidump fajlovima.
.DESCRIPTION
    Pronalazi C:\Windows\Minidump datoteke, mapira ih sa sistemskim BugCheck
    zapisima (Event ID 1001) i izvlaci Stop kodove i parametre.
#>

[CmdletBinding()]
param (
    [int]$TopCount = 5
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "               IZVESTAJ O BSOD PADU SISTEMA (MINIDUMP)            " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

$minidumpDir = "C:\Windows\Minidump"
$memoryDump = "C:\Windows\MEMORY.DMP"

$dmpFiles = @()
if (Test-Path $minidumpDir) {
    $dmpFiles = Get-ChildItem -Path $minidumpDir -Filter "*.dmp" | Sort-Object LastWriteTime -Descending
}

Write-Host "[*] Pronadjeno minidump datoteka u $minidumpDir : $($dmpFiles.Count)" -ForegroundColor White
if (Test-Path $memoryDump) {
    $fullDump = Get-Item $memoryDump
    $sizeMB = [math]::Round($fullDump.Length / 1MB, 2)
    Write-Host "[*] Pronadjen puni MEMORY.DMP ($sizeMB MB), poslednja izmena: $($fullDump.LastWriteTime)" -ForegroundColor Yellow
}

if ($dmpFiles.Count -gt 0) {
    Write-Host "`nNajnoviji Minidump fajlovi:" -ForegroundColor Yellow
    foreach ($file in ($dmpFiles | Select-Object -First $TopCount)) {
        Write-Host "  - $($file.Name) | Kreiran: $($file.LastWriteTime) | Velicina: $([math]::Round($file.Length/1KB, 1)) KB" -ForegroundColor Cyan
    }
} else {
    Write-Host "  [OK] Nema minidump fajlova u $minidumpDir." -ForegroundColor Green
}

# Citanje BugCheck dogadjaja iz System Event Log-a (Event ID 1001 - Save Dump / BugCheck)
Write-Host "`n[*] Analiza BugCheck zapisa iz Event Log-a (Istorija plavih ekrana):" -ForegroundColor Yellow
try {
    $bugCheckEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Id = 1001
    } -MaxEvents $TopCount -ErrorAction SilentlyContinue

    if ($bugCheckEvents) {
        foreach ($evt in $bugCheckEvents) {
            Write-Host "  [BSOD ZAPIS] $($evt.TimeCreated)" -ForegroundColor Red
            $lines = $evt.Message -split "`r`n"
            foreach ($line in $lines) {
                if ($line -match "bugcheck|0x[0-9a-fA-F]+|dump|driver" -or $line.Trim().Length -gt 0) {
                    Write-Host "    $($line.Trim())" -ForegroundColor Gray
                }
            }
            Write-Host "    --------------------------------------------------------------" -ForegroundColor DarkGray
        }
    } else {
        # Fallback na WER (Windows Error Reporting) iz Application dnevnika
        $werEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            ProviderName = 'Windows Error Reporting'
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        $foundWer = $false
        foreach ($w in $werEvents) {
            if ($w.Message -match "BlueScreen|BugCheck|0x[0-9a-fA-F]{8}") {
                $foundWer = $true
                Write-Host "  [WER BSOD] $($w.TimeCreated) : $($w.Message.Substring(0, [math]::Min(120, $w.Message.Length)))" -ForegroundColor Yellow
            }
        }
        if (-not $foundWer) {
            Write-Host "  [OK] Nema zabelezenih BugCheck ili BlueScreen zapisa u dnevniku." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [!] Nije moguce ucitati BugCheck dogadjaje: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "==================================================================" -ForegroundColor Cyan
