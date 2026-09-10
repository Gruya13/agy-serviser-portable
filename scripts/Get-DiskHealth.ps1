<#
.SYNOPSIS
    Prikuplja detaljne podatke o zdravlju i SMART parametrima diskova (SSD, NVMe, HDD).
.DESCRIPTION
    Kompatibilno sa Windows PowerShell 5.1 i PowerShell 7+. Koristi nativne Storage module
    bez potrebe za eksternim alatima.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "                IZVESTAJ O ZDRAVLJU DISKOVA (SMART/NVMe)          " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan

try {
    $physicalDisks = Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, @{Name="SizeGB";Expression={[math]::Round($_.Size / 1GB, 2)}}

    foreach ($disk in $physicalDisks) {
        Write-Host "`n[DISK #$($disk.DeviceId)] $($disk.FriendlyName)" -ForegroundColor Green
        Write-Host "  - Tip medijuma:      $($disk.MediaType) (Interfejs: $($disk.BusType))"
        Write-Host "  - Kapacitet:         $($disk.SizeGB) GB"
        Write-Host "  - Zdravstveni status:$($disk.HealthStatus) (Operativni: $($disk.OperationalStatus))"

        # Citanje brojackih/SMART pouzdanosti
        $reliability = Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk -DeviceId $disk.DeviceId)
        if ($reliability) {
            Write-Host "  - Temperatura:       $($reliability.Temperature) C"
            if ($null -ne $reliability.Wear) {
                Write-Host "  - Istrosenost (Wear):$($reliability.Wear) %"
            }
            Write-Host "  - Radni sati:        $($reliability.PowerOnHours) h"
            Write-Host "  - Ukupno gresaka:    Citanje: $($reliability.ReadErrorsTotal) | Pisanje: $($reliability.WriteErrorsTotal)"
            if ($reliability.ReadErrorsUncorrected -gt 0 -or $reliability.WriteErrorsUncorrected -gt 0) {
                Write-Host "  [!] UPOZORENJE: Postoje neispravljive greske na disku!" -ForegroundColor Red
                Write-Host "      Neispravljive citanje: $($reliability.ReadErrorsUncorrected)" -ForegroundColor Red
                Write-Host "      Neispravljive pisanje: $($reliability.WriteErrorsUncorrected)" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "[!] Greska pri ocitavanju fizickih diskova preko Storage modula: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Informacije o particijama i slobodnom prostoru
Write-Host "`n------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "STANJE LOGICKIH PARTICIJA:" -ForegroundColor Yellow
try {
    $volumes = Get-PSDrive -PSProvider FileSystem | Select-Object Name, Root, @{Name="FreeGB";Expression={[math]::Round($_.Free / 1GB, 2)}}, @{Name="UsedGB";Expression={[math]::Round($_.Used / 1GB, 2)}}, @{Name="TotalGB";Expression={[math]::Round(($_.Free + $_.Used) / 1GB, 2)}}, @{Name="FreePercent";Expression={[math]::Round(($_.Free / ($_.Free + $_.Used)) * 100, 1)}}
    
    foreach ($vol in $volumes) {
        $color = if ($vol.FreePercent -lt 10) { "Red" } elseif ($vol.FreePercent -lt 20) { "Yellow" } else { "White" }
        Write-Host "  [$($vol.Name):] Ukupno: $($vol.TotalGB) GB | Slobodno: $($vol.FreeGB) GB ($($vol.FreePercent)%)" -ForegroundColor $color
    }
} catch {
    Write-Host "[!] Nije moguce ocitati logicke particije: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "==================================================================" -ForegroundColor Cyan
