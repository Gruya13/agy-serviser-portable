<#
.SYNOPSIS
    Automatska identifikacija klijentskog racunara i kreiranje servisnog kartona.
.DESCRIPTION
    Ocitava serijski broj (BIOS/Maticna ploca/UUID), model, proizvodjaca i hardversku
    specifikaciju. Kreira i azurira folder uredjaja (devices\<DeviceTag>) na USB-u,
    kao i dokumente DEVICE_INFO.md i SERVISNI_DNEVNIK.md.
#>

[CmdletBinding()]
param (
    [string]$TargetDevicesDir
)

$ErrorActionPreference = "SilentlyContinue"

if (-not $TargetDevicesDir) {
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    $TargetDevicesDir = Join-Path $scriptRoot "devices"
}

# 1. Ocitavanje sistemskih CIM objekata
$bios = Get-CimInstance Win32_Bios -ErrorAction SilentlyContinue
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
$bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
$cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
$disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue

# 2. Odredjivanje pouzdanog serijskog broja
$rawSerial = $bios.SerialNumber
$isInvalidSerial = {
    param($s)
    if (-not $s) { return $true }
    $clean = $s.Trim().ToLower()
    return ($clean -eq "" -or
            $clean -match "default|to be filled|none|o.e.m|oem|000000|system serial|chassis serial|not applicable|unknown")
}

$chosenSerial = ""
if (-not (& $isInvalidSerial $rawSerial)) {
    $chosenSerial = $rawSerial.Trim()
} elseif (-not (& $isInvalidSerial $bb.SerialNumber)) {
    $chosenSerial = $bb.SerialNumber.Trim()
} elseif ($csp.UUID -and $csp.UUID -ne "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") {
    $cleanUUID = $csp.UUID.Replace("-", "")
    $shortUUID = if ($cleanUUID.Length -ge 8) { $cleanUUID.Substring($cleanUUID.Length - 8) } else { $cleanUUID }
    $chosenSerial = "UUID-$shortUUID"
} else {
    $chosenSerial = "PC-$($env:COMPUTERNAME)"
}

# 3. Formiranje cistih naziva za DeviceTag
$cleanMfr = if ($cs.Manufacturer) { ($cs.Manufacturer -replace '[^\w\-]', '_').Trim('_') } else { "Generic" }
if ($cleanMfr.Length -gt 15) { $cleanMfr = $cleanMfr.Substring(0, 15).Trim('_') }

$cleanModel = if ($cs.Model) { ($cs.Model -replace '[^\w\-]', '_').Trim('_') } else { "System" }
if ($cleanModel.Length -gt 20) { $cleanModel = $cleanModel.Substring(0, 20).Trim('_') }

$safeSerial = ($chosenSerial -replace '[^\w\-]', '').Trim()
if ($safeSerial.Length -gt 20) { $safeSerial = $safeSerial.Substring(0, 20) }

$deviceTag = "${cleanMfr}_${cleanModel}_${safeSerial}"
$deviceFolder = Join-Path $TargetDevicesDir $deviceTag

# 4. Provera da li uredjaj vec postoji u bazi servisa
$isExistingDevice = Test-Path $deviceFolder
if (-not $isExistingDevice) {
    New-Item -ItemType Directory -Path $deviceFolder -Force | Out-Null
}

$reportsDir = Join-Path $deviceFolder "reports"
$sessionsDir = Join-Path $deviceFolder "sessions"
if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
if (-not (Test-Path $sessionsDir)) { New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null }

# 5. Formatiranje hardverskih specifikacija
$ramGB = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { "N/A" }
$cpuName = if ($cpu.Name) { $cpu.Name.Trim() } else { "N/A" }
$osName = if ($os.Caption) { "$($os.Caption) ($($os.OSArchitecture)) - Build $($os.BuildNumber)" } else { "N/A" }

$gpuList = @()
if ($gpus) {
    foreach ($g in $gpus) {
        if ($g.Name) { $gpuList += $g.Name.Trim() }
    }
}
$gpuString = if ($gpuList.Count -gt 0) { $gpuList -join ", " } else { "N/A" }

$diskList = @()
if ($disks) {
    foreach ($d in $disks) {
        $sizeGB = [math]::Round($d.Size / 1GB, 0)
        $diskList += "$($d.Model.Trim()) (${sizeGB} GB)"
    }
}
$diskString = if ($diskList.Count -gt 0) { $diskList -join " | " } else { "N/A" }

# 6. Kreiranje / Azuriranje DEVICE_INFO.md
$deviceInfoPath = Join-Path $deviceFolder "DEVICE_INFO.md"
$currentTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$deviceInfoContent = @"
# Servisni Karton Uredjaja: $deviceTag

- **Oznaka uredjaja (DeviceTag):** `$deviceTag`
- **Proizvodjac:** $($cs.Manufacturer)
- **Model racunara / ploce:** $($cs.Model) (Ploca: $($bb.Product))
- **Serijski broj:** `$chosenSerial`
- **Hardverski UUID:** $($csp.UUID)
- **Naziv u sistemu (ComputerName):** $($env:COMPUTERNAME)
- **Poslednja sinhronizacija:** $currentTime

---

## Hardverska Specifikacija

| Komponenta | Podaci |
| :--- | :--- |
| **Procesor (CPU)** | $cpuName ($($cpu.NumberOfCores) jezgara / $($cpu.NumberOfLogicalProcessors) niti) |
| **Radna memorija (RAM)** | $ramGB GB |
| **Graficka karta (GPU)** | $gpuString |
| **Skladiste (Diskovi)** | $diskString |
| **Operativni sistem** | $osName |
| **BIOS verzija** | $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate)) |

---
*Fajl je automatski generisan od strane Antigravity CLI Prenosivog Servisnog Asistenta.*
"@

[System.IO.File]::WriteAllText($deviceInfoPath, $deviceInfoContent)

# 7. Kreiranje / Dopuna SERVISNI_DNEVNIK.md
$dnevnikPath = Join-Path $deviceFolder "SERVISNI_DNEVNIK.md"
if (-not (Test-Path $dnevnikPath)) {
    $dnevnikInitial = @"
# Servisni Dnevnik Intervencija: $deviceTag

Ovaj dokument sadrzi istoriju svih servisnih intervencija i dijagnostickih nalaza za ovaj racunar.

---

### [Datum: $currentTime] - Prijem na servis (Prvi unos)
- **Status:** Otvoren novi servisni nalog.
- **Inicijalna konfiguracija:** $cpuName, $ramGB GB RAM, $diskString.
- **Zabelezeno od strane:** Servis AI Asistent.

"@
    [System.IO.File]::WriteAllText($dnevnikPath, $dnevnikInitial)
} else {
    # Dodajemo zabelezku o novoj servisnoj sesiji
    $sessionNote = "`n### [Datum: $currentTime] - Nova servisna sesija`n- **Racunar ponovo prikljucen na servisni USB.**`n"
    [System.IO.File]::AppendAllText($dnevnikPath, $sessionNote)
}

# 8. Povratni objekat
return [PSCustomObject]@{
    DeviceTag        = $deviceTag
    DeviceFolder     = $deviceFolder
    SerialNumber     = $chosenSerial
    Manufacturer     = $cs.Manufacturer
    Model            = $cs.Model
    IsExistingDevice = $isExistingDevice
    DeviceInfoPath   = $deviceInfoPath
    DnevnikPath      = $dnevnikPath
    ReportsDir       = $reportsDir
    SessionsDir      = $sessionsDir
    RAMGB            = $ramGB
    CPU              = $cpuName
}
