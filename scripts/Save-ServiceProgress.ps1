<#
.SYNOPSIS
    Operativno snimanje nalaza (Live Checkpoint) i ažuriranje statusa uređaja na Servis Hub-u.
.DESCRIPTION
    Ovu skriptu poziva AGY Servis Asistent ili serviser u toku rada na računaru čim
    otkrije ključnu anomaliju, završi fazu dijagnostike ili donese servisni zaključak.
    Upisuje zabelešku u lokalni SERVISNI_DNEVNIK.md i šalje checkpoint na centralni Servis Hub.
.PARAMETER Summary
    Opis dijagnostičkog nalaza ili uočene anomalije (npr. 'Otkriven 1 loš sektor na NVMe disku').
.PARAMETER Status
    Servisni status mašine: U_DIJAGNOSTICI, KVAR_POTVRDJEN, CEKA_DELOVE, ISPRAVAN, COMPLETED.
.PARAMETER ToolsExecuted
    Lista skripti i alata koji su korišćeni (npr. 'Get-DiskHealth.ps1', 'Get-MinidumpReport.ps1').
.PARAMETER DeviceFolder
    Putanja do radnog foldera računara (podrazumevano uzima iz $env:CURRENT_DEVICE_DIR).
.PARAMETER DeviceTag
    Oznaka računara (podrazumevano uzima iz $env:CURRENT_DEVICE_TAG).
.EXAMPLE
    .\scripts\Save-ServiceProgress.ps1 -Summary "Otkriven otkaz NVMe kontrolera" -Status "KVAR_POTVRDJEN" -ToolsExecuted @("Get-DiskHealth.ps1")
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Summary,

    [ValidateSet("U_DIJAGNOSTICI", "KVAR_POTVRDJEN", "CEKA_DELOVE", "ISPRAVAN", "COMPLETED", "CRITICAL_ISSUE", "WARNING")]
    [string]$Status = "U_DIJAGNOSTICI",

    [string[]]$ToolsExecuted = @(),
    [string]$DeviceFolder,
    [string]$DeviceTag
)

$ErrorActionPreference = "Continue"

$scriptDir = $PSScriptRoot.TrimEnd('\')
$syncScript = Join-Path $scriptDir "Sync-ServiceHub.ps1"

if (-not (Test-Path $syncScript)) {
    Write-Host "[X] GRESKA: Skripta '$syncScript' nije pronadjena!" -ForegroundColor Red
    return
}

# Razresavanje radnog foldera i taga
$targetFolder = $DeviceFolder
if (-not $targetFolder -and $env:CURRENT_DEVICE_DIR) {
    $targetFolder = $env:CURRENT_DEVICE_DIR
}

$targetTag = $DeviceTag
if (-not $targetTag -and $env:CURRENT_DEVICE_TAG) {
    $targetTag = $env:CURRENT_DEVICE_TAG
}

# Ako i dalje nema foldera, potrazi u USB devices/
if (-not $targetFolder) {
    $usbRoot = Split-Path $scriptDir -Parent
    $devicesDir = Join-Path $usbRoot "devices"
    if (Test-Path $devicesDir) {
        $recent = Get-ChildItem -Path $devicesDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($recent) {
            $targetFolder = $recent.FullName
            if (-not $targetTag) { $targetTag = $recent.Name }
        }
    }
}

if (-not $targetFolder -or -not (Test-Path $targetFolder)) {
    Write-Host "[X] GRESKA: Nije moguce odrediti radni folder uredjaja (-DeviceFolder ili `$env:CURRENT_DEVICE_DIR)!" -ForegroundColor Red
    return
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "         SERVIS AI: SNIMANJE DIJAGNOSTICKOG NALAZA                " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Nalaz:  $Summary" -ForegroundColor White
Write-Host "  Status: $Status" -ForegroundColor Yellow
if ($ToolsExecuted -and $ToolsExecuted.Count -gt 0) {
    Write-Host "  Alati:  $($ToolsExecuted -join ', ')" -ForegroundColor Gray
}
Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

& $syncScript -Checkpoint `
              -DeviceFolder $targetFolder `
              -DeviceTag $targetTag `
              -Summary $Summary `
              -Status $Status `
              -ToolsExecuted $ToolsExecuted

Write-Host "==================================================================" -ForegroundColor Cyan
