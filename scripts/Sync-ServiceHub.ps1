<#
.SYNOPSIS
    Dvosmerna sinhronizacija sesija i istorije izmedju Antigravity servisnog asistenta i ServisHub-a.
.DESCRIPTION
    Implementira ADR-0003:
    - UDP Auto-Discovery ServisHub-a na portu 8888 uz fallback na static_url iz config/settings.json.
    - Pre-flight Pull: Ocitavanje centralne istorije intervencija (GET /api/devices/{tag}/history).
    - Post-flight Push: Slanje zavrsene dijagnosticke sesije (POST /api/devices/{tag}/agy-session).
    - Offline queue: Ako Hub nije dostupan, sesija se cuva u pending_sync/ i salje naknadno (-FlushPending).
.PARAMETER Pull
    Preuzima i prikazuje istoriju intervencija sa ServisHub-a za dati uredjaj.
.PARAMETER Push
    Pakuje i salje tekucu servisnu sesiju na ServisHub.
.PARAMETER FlushPending
    Salje sve zaostale sesije iz offline reda cekanja (pending_sync/).
.PARAMETER DeviceTag
    Jedinstvena oznaka racunara (npr. Dell_Inc__Latitude_5420_8G7X123).
.PARAMETER SerialNumber
    Serijski broj racunara (za pretragu istorije po serijskom broju).
.PARAMETER Register
    Pre-flight registracija novog radionickog kartona na ServisHub-u pre starta sesije.
.PARAMETER Checkpoint
    Slanje operativne medjubelezke (nalaza) i azuriranje statusa uredjaja u toku rada.
.PARAMETER Summary
    Opis nalaza za checkpoint.
.PARAMETER Status
    Status racunara (npr. U_DIJAGNOSTICI, KVAR_POTVRDJEN, CEKA_DELOVE, ISPRAVAN).
.PARAMETER ToolsExecuted
    Lista naziva alata i skripti pokrenutih pre checkpointa.
.PARAMETER DeviceFolder
    Putanja do radnog foldera uredjaja (devices/<DeviceTag>).
.PARAMETER HubUrl
    Eksplicitni URL ServisHub-a (zaobilazi UDP discovery i podesavanja).
#>

[CmdletBinding()]
param (
    [switch]$Pull,
    [switch]$Push,
    [switch]$Register,
    [switch]$Checkpoint,
    [switch]$FlushPending,
    [string]$DeviceTag,
    [string]$SerialNumber,
    [string]$DeviceFolder,
    [string]$Summary,
    [string]$Status,
    [string[]]$ToolsExecuted,
    [string]$HubUrl
)

$ErrorActionPreference = "SilentlyContinue"

# -----------------------------------------------------------------------------
# 1. POMOCNE FUNKCIJE: Putanje i Konfiguracija
# -----------------------------------------------------------------------------

function Get-UsbRoot {
    if ($PSScriptRoot) {
        return (Split-Path $PSScriptRoot -Parent)
    }
    return (Get-Location).Path
}

function Get-SettingsData {
    param ([string]$RootPath)
    $settingsPath = Join-Path $RootPath "config\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($settingsPath, [System.Text.Encoding]::UTF8)
            return ($raw | ConvertFrom-Json)
        } catch {}
    }
    return $null
}

function Get-PendingQueueDir {
    param ([string]$RootPath)
    $dir = Join-Path $RootPath "pending_sync"
    if (-not (Test-Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        } catch {
            # Ako je USB zakljucan (Write-Protect), prebaci u %TEMP%
            $dir = Join-Path $env:TEMP "pending_sync"
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
    return $dir
}

# -----------------------------------------------------------------------------
# 2. DETEKCIJA SERVIS HUB-A: UDP Auto-Discovery & Fallback
# -----------------------------------------------------------------------------

function Find-ServisHubUdp {
    param (
        [int]$Port = 8888,
        [int]$TimeoutMs = 1500
    )

    $discoveredUrl = $null
    $udpClient = $null

    try {
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.EnableBroadcast = $true
        $udpClient.Client.ReceiveTimeout = $TimeoutMs

        $broadcastEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $Port)
        # Slanje upita koji je prepoznatljiv svim verzijama Hub discovery osluskivaca
        $payload = [System.Text.Encoding]::UTF8.GetBytes("SERVIS_HUB_DISCOVER SERVIS_DISCOVER GWADT_DISCOVER")
        [void]$udpClient.Send($payload, $payload.Length, $broadcastEp)

        $remoteEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $recvBytes = $udpClient.Receive([ref]$remoteEp)

        if ($recvBytes -and $recvBytes.Length -gt 0) {
            $respText = [System.Text.Encoding]::UTF8.GetString($recvBytes).Trim()
            $senderIp = $remoteEp.Address.ToString()

            # Pokusaj 1: Parsiranje kao JSON odgovor
            try {
                $jsonResp = $respText | ConvertFrom-Json -ErrorAction Stop
                if ($jsonResp.url) {
                    $discoveredUrl = $jsonResp.url
                } elseif ($jsonResp.port) {
                    $hostIp = if ($jsonResp.ip) { $jsonResp.ip } elseif ($jsonResp.host) { $jsonResp.host } else { $senderIp }
                    $discoveredUrl = "http://${hostIp}:$($jsonResp.port)"
                }
            } catch {}

            # Pokusaj 2: Tekstualni odgovori tipa "GWADT_HUB_OFFER port=8080..."
            if (-not $discoveredUrl) {
                if ($respText -match "port=(\d+)") {
                    $httpPort = $matches[1]
                    $discoveredUrl = "http://${senderIp}:${httpPort}"
                }
            }
        }
    } catch {
        # Timeout ili mrezno ogranicenje - nastavljamo bez prekida
    } finally {
        if ($udpClient) {
            try { $udpClient.Close() } catch {}
        }
    }

    return $discoveredUrl
}

function Resolve-HubUrl {
    param (
        [string]$ExplicitUrl,
        [string]$RootPath
    )

    if ($ExplicitUrl) {
        return $ExplicitUrl.TrimEnd('/')
    }

    $settings = Get-SettingsData -RootPath $RootPath

    $autoDiscover = $true
    $discoveryPort = 8888
    $staticUrl = "http://localhost:8000"

    if ($settings -and $settings.servis_hub) {
        if ($null -ne $settings.servis_hub.auto_discovery) {
            $autoDiscover = [bool]$settings.servis_hub.auto_discovery
        }
        if ($settings.servis_hub.discovery_port) {
            $discoveryPort = [int]$settings.servis_hub.discovery_port
        }
        if ($settings.servis_hub.static_url) {
            $staticUrl = [string]$settings.servis_hub.static_url
        }
    }

    if ($autoDiscover) {
        $discovered = Find-ServisHubUdp -Port $discoveryPort -TimeoutMs 1500
        if ($discovered) {
            return $discovered.TrimEnd('/')
        }
    }

    return $staticUrl.TrimEnd('/')
}

# -----------------------------------------------------------------------------
# 3. POMOCNE FUNKCIJE: Parsiranje fajlova uredjaja
# -----------------------------------------------------------------------------

function Get-HardwareProfile {
    param ([string]$DeviceDirPath)

    $hw = [ordered]@{
        manufacturer = "Generic"
        model        = "System"
        cpu          = "N/A"
        ram_gb       = 0.0
        disks        = "N/A"
        os           = "N/A"
        bios         = "N/A"
        serial       = "UNKNOWN"
        tag          = ""
    }

    $infoPath = Join-Path $DeviceDirPath "DEVICE_INFO.md"
    if (Test-Path $infoPath) {
        try {
            $content = [System.IO.File]::ReadAllText($infoPath, [System.Text.Encoding]::UTF8)

            if ($content -match '\*\*Oznaka uredjaja \(DeviceTag\):\*\*\s*`?([^\r\n`]+)`?') {
                $hw.tag = $matches[1].Trim()
            }
            if ($content -match '\*\*Proizvodjac:\*\*\s*([^\r\n]+)') {
                $hw.manufacturer = $matches[1].Trim()
            }
            if ($content -match '\*\*Model racunara / ploce:\*\*\s*([^\r\n(]+)') {
                $hw.model = $matches[1].Trim()
            }
            if ($content -match '\*\*Serijski broj:\*\*\s*`?([^\r\n`]+)`?') {
                $hw.serial = $matches[1].Trim()
            }
            if ($content -match '\|\s*\*\*Procesor \(CPU\)\*\*\s*\|\s*([^|\r\n]+)\|') {
                $hw.cpu = $matches[1].Trim()
            }
            if ($content -match '\|\s*\*\*Radna memorija \(RAM\)\*\*\s*\|\s*([0-9.]+)\s*GB') {
                $parsedRam = 0.0
                if ([double]::TryParse($matches[1].Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedRam)) {
                    $hw.ram_gb = [math]::Round($parsedRam, 1)
                }
            }
            if ($content -match '\|\s*\*\*Skladiste \(Diskovi\)\*\*\s*\|\s*([^|\r\n]+)\|') {
                $hw.disks = $matches[1].Trim()
            }
            if ($content -match '\|\s*\*\*Operativni sistem\*\*\s*\|\s*([^|\r\n]+)\|') {
                $hw.os = $matches[1].Trim()
            }
            if ($content -match '\|\s*\*\*BIOS verzija\*\*\s*\|\s*([^|\r\n]+)\|') {
                $hw.bios = $matches[1].Trim()
            }
        } catch {}
    }

    return $hw
}

function Get-LatestDnevnikEntry {
    param ([string]$DeviceDirPath)

    $dnevnikPath = Join-Path $DeviceDirPath "SERVISNI_DNEVNIK.md"
    if (Test-Path $dnevnikPath) {
        try {
            $content = [System.IO.File]::ReadAllText($dnevnikPath, [System.Text.Encoding]::UTF8)
            $idx = $content.LastIndexOf("### [Datum:")
            if ($idx -ge 0) {
                return $content.Substring($idx).Trim()
            }
            return $content.Trim()
        } catch {}
    }
    return ""
}

function Get-DiagnosticReportData {
    param ([string]$DeviceDirPath)

    $res = @{
        report_markdown = ""
        summary         = ""
        status          = "COMPLETED"
        tools           = @()
    }

    $reportPath = Join-Path $DeviceDirPath "reports\IZVESTAJ_DIJAGNOSTIKE.md"
    if (-not (Test-Path $reportPath)) {
        # Proveri da li ima bilo koji drugi .md u reports/
        $repFiles = Get-ChildItem (Join-Path $DeviceDirPath "reports\*.md") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($repFiles -and $repFiles.Count -gt 0) {
            $reportPath = $repFiles[0].FullName
        }
    }

    if (Test-Path $reportPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($reportPath, [System.Text.Encoding]::UTF8)
            $res.report_markdown = $raw

            # Ekstrakcija Root Cause / Sazetka
            if ($raw -match '(?i)\*\*(?:Primarni uzrok \(Root Cause\)|Root Cause|Primarni uzrok):\*\*\s*([^\r\n]+)') {
                $res.summary = $matches[1].Trim()
            } elseif ($raw -match '(?i)##\s*(?:Zaključak|Zakljucak|Root Cause)[^\r\n]*\r?\n([^\r\n#]+)') {
                $res.summary = $matches[1].Trim()
            }

            # Odredjivanje statusa
            if ($raw -match '(?i)CRITICAL|KRITIČNO|KRITICNO|Hardware Failure|Otkaz diska') {
                $res.status = "CRITICAL_ISSUE"
            } elseif ($raw -match '(?i)WARNING|UPOZORENJE|Warning') {
                $res.status = "WARNING"
            } else {
                $res.status = "COMPLETED"
            }

            # Prepoznavanje pokrenutih servisnih skripti
            $scriptMatches = [regex]::Matches($raw, '(?i)(Get-\w+|Test-\w+|Find-\w+|Protect-\w+)\.ps1')
            $foundTools = @()
            foreach ($m in $scriptMatches) {
                if ($foundTools -notcontains $m.Value) {
                    $foundTools += $m.Value
                }
            }
            $res.tools = $foundTools
        } catch {}
    }

    return $res
}

function Export-HubHistoryMarkdown {
    param (
        [object]$History,
        [string]$TargetFolder
    )

    if (-not $TargetFolder -or -not (Test-Path $TargetFolder)) { return }

    $destPath = Join-Path $TargetFolder "SERVIS_HUB_HISTORY.md"
    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("# 🏛️ Servis Hub Istorija: $($History.device_tag)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> [!NOTE]")
    [void]$sb.AppendLine("> Ovi podaci su automatski preuzeti sa centralnog Servis Hub-a.")
    [void]$sb.AppendLine("> Koristi ove nalaze za prepoznavanje recidivnih kvarova i prethodnih zahvata.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- **Proizvodjac i Model:** $($History.manufacturer) $($History.model)")
    [void]$sb.AppendLine("- **Serijski Broj:** `$($History.serial_number)`")
    [void]$sb.AppendLine("- **Prvi Prijem:** $($History.first_seen)")
    [void]$sb.AppendLine("- **Poslednji Prijem:** $($History.last_seen)")
    [void]$sb.AppendLine("- **Ukupno Prethodnih Intervencija:** $($History.total_interventions)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 📜 Hronologija Prethodnih Intervencija")
    [void]$sb.AppendLine("")

    if ($History.interventions -and $History.interventions.Count -gt 0) {
        foreach ($item in $History.interventions) {
            [void]$sb.AppendLine("### [$($item.date)] Status: [$($item.status)]")
            if ($item.summary) {
                [void]$sb.AppendLine("- **Sazetak:** $($item.summary)")
            }
            if ($item.tools_used) {
                $toolsStr = ($item.tools_used -join ", ")
                [void]$sb.AppendLine("- **Korisceni alati:** $toolsStr")
            }
            [void]$sb.AppendLine("")
        }
    } else {
        [void]$sb.AppendLine("Nema evidentiranih pojedinacnih intervencija.")
        [void]$sb.AppendLine("")
    }

    if ($History.dnevnik_markdown) {
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## 📑 Servisni Dnevnik sa Hub-a")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine($History.dnevnik_markdown)
    }

    try {
        [System.IO.File]::WriteAllText($destPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
        Write-Host "  [OK] Generisan servisni kontekst: $destPath" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Upozorenje pri generisanju SERVIS_HUB_HISTORY.md: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Merge-HubDnevnik {
    param (
        [object]$History,
        [string]$TargetFolder
    )

    if (-not $TargetFolder -or -not (Test-Path $TargetFolder)) { return }
    if (-not $History.dnevnik_markdown) { return }

    $dnevnikPath = Join-Path $TargetFolder "SERVISNI_DNEVNIK.md"
    $hubDnevnik = [string]$History.dnevnik_markdown

    if (-not (Test-Path $dnevnikPath)) {
        try {
            [System.IO.File]::WriteAllText($dnevnikPath, $hubDnevnik, [System.Text.Encoding]::UTF8)
            Write-Host "  [OK] Preuzet servisni dnevnik sa Servis Hub-a: $dnevnikPath" -ForegroundColor Green
        } catch {}
        return
    }

    try {
        $localDnevnik = [System.IO.File]::ReadAllText($dnevnikPath, [System.Text.Encoding]::UTF8)
        $pattern = '(?ms)(### \[Datum:[^\r\n]+\].*?)(?=(?:### \[Datum:|\Z))'
        $hubMatches = [regex]::Matches($hubDnevnik, $pattern)
        
        $entriesToAdd = @()
        foreach ($hm in $hubMatches) {
            $entryText = $hm.Value.Trim()
            if ($entryText -match '^(### \[Datum:[^\]\r\n]+\])') {
                $headerSignature = $matches[1]
                if ($localDnevnik -notmatch [regex]::Escape($headerSignature)) {
                    $entriesToAdd += $entryText
                }
            }
        }

        if ($entriesToAdd.Count -gt 0) {
            $headerEndIdx = $localDnevnik.IndexOf("---")
            if ($headerEndIdx -ge 0) {
                $afterHeader = $headerEndIdx + 3
                $prefix = $localDnevnik.Substring(0, $afterHeader)
                $suffix = $localDnevnik.Substring($afterHeader)
                $mergedText = $prefix + "`n`n" + ($entriesToAdd -join "`n`n") + "`n`n" + $suffix.TrimStart("`r", "`n")
            } else {
                $mergedText = ($entriesToAdd -join "`n`n") + "`n`n" + $localDnevnik
            }
            [System.IO.File]::WriteAllText($dnevnikPath, $mergedText.Trim() + "`n", [System.Text.Encoding]::UTF8)
            Write-Host "  [OK] Dnevnik uskladjen sa Servis Hub-om (dodato $($entriesToAdd.Count) novih zapisa)." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Upozorenje pri spajanju servisnog dnevnika: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# 4. IMPLEMENTACIJA AKCIJA: Pull, Push, Register, Checkpoint i FlushPending
# -----------------------------------------------------------------------------

function Invoke-HubPull {
    param (
        [string]$TargetHubUrl,
        [string]$TargetDeviceTag,
        [string]$TargetSerial,
        [string]$TargetFolder
    )

    if ($TargetFolder -and (Test-Path $TargetFolder)) {
        $resolvedFolder = (Resolve-Path $TargetFolder -ErrorAction SilentlyContinue).Path
        if ($resolvedFolder) { $TargetFolder = $resolvedFolder }
    }

    if (-not $TargetDeviceTag -and $TargetFolder) {
        $hw = Get-HardwareProfile -DeviceDirPath $TargetFolder
        $TargetDeviceTag = if ($hw.tag) { $hw.tag } else { Split-Path $TargetFolder -Leaf }
        if (-not $TargetSerial -and $hw.serial -ne "UNKNOWN") {
            $TargetSerial = $hw.serial
        }
    }

    $pullUrl = ""
    if ($TargetDeviceTag) {
        $encodedTag = [System.Uri]::EscapeDataString($TargetDeviceTag)
        $pullUrl = "$TargetHubUrl/api/devices/$encodedTag/history"
    } elseif ($TargetSerial) {
        $encodedSerial = [System.Uri]::EscapeDataString($TargetSerial)
        $pullUrl = "$TargetHubUrl/api/devices/by-serial/$encodedSerial/history"
    } else {
        Write-Host "[!] Za -Pull je neophodno navesti -DeviceTag, -SerialNumber ili -DeviceFolder." -ForegroundColor Yellow
        return $null
    }

    Write-Host "[*] Provera prethodne servisne istorije na ServisHub-u..." -ForegroundColor Cyan
    Write-Host "    Povezujem se na: $pullUrl" -ForegroundColor DarkGray

    try {
        $response = Invoke-RestMethod -Uri $pullUrl -Method Get -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    } catch {
        Write-Host "[!] Upozorenje: ServisHub nije dostupan na $TargetHubUrl ($($_.Exception.Message))" -ForegroundColor Yellow
        Write-Host "    Nastavlja se rad sa lokalnim servisnim podacima sa USB medijuma." -ForegroundColor Gray
        return $null
    }

    if ($null -eq $response) {
        Write-Host "[!] ServisHub je vratio prazan odgovor." -ForegroundColor Yellow
        return $null
    }

    if ($response.is_registered -eq $true) {
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Cyan
        Write-Host "       PRONADJENA SERVISNA ISTORIJA NA SERVIS HUB-U               " -ForegroundColor Yellow
        Write-Host "==================================================================" -ForegroundColor Cyan
        Write-Host "  Uredjaj:             $($response.manufacturer) $($response.model)" -ForegroundColor White
        Write-Host "  Oznaka (DeviceTag):  $($response.device_tag)" -ForegroundColor Gray
        Write-Host "  Serijski broj:       $($response.serial_number)" -ForegroundColor Green
        Write-Host "  Prvi prijem:         $($response.first_seen)" -ForegroundColor DarkGray
        Write-Host "  Poslednji prijem:    $($response.last_seen)" -ForegroundColor DarkGray
        Write-Host "  Ukupno intervencija: $($response.total_interventions)" -ForegroundColor Cyan
        Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

        if ($response.interventions -and $response.interventions.Count -gt 0) {
            Write-Host "PRETHODNE ZABELEZENE INTERVENCIJE:" -ForegroundColor Yellow
            foreach ($item in $response.interventions) {
                $statusColor = switch ($item.status) {
                    "CRITICAL_ISSUE" { "Red" }
                    "WARNING"        { "Yellow" }
                    "COMPLETED"      { "Green" }
                    default          { "White" }
                }
                Write-Host "  [$($item.date)] Status: [$($item.status)]" -ForegroundColor $statusColor
                if ($item.summary) {
                    Write-Host "    Sazetak: $($item.summary)" -ForegroundColor White
                }
                if ($item.tools_used) {
                    $toolsText = ($item.tools_used -join ", ")
                    Write-Host "    Alati:   $toolsText" -ForegroundColor DarkGray
                }
                Write-Host ""
            }
        } else {
            Write-Host "  Nema pojedinacnih stavki intervencija u istorijatu." -ForegroundColor Gray
        }
        Write-Host "==================================================================" -ForegroundColor Cyan
        Write-Host ""

        if ($TargetFolder) {
            Export-HubHistoryMarkdown -History $response -TargetFolder $TargetFolder
            Merge-HubDnevnik -History $response -TargetFolder $TargetFolder
        }
    } else {
        # Fallback pretraga po serijskom broju
        $foundBySerial = $false
        if ($TargetSerial -and $TargetSerial -ne "UNKNOWN" -and $TargetDeviceTag) {
            $fallbackSerialUrl = "$TargetHubUrl/api/devices/by-serial/$([System.Uri]::EscapeDataString($TargetSerial))/history"
            try {
                $fallbackResp = Invoke-RestMethod -Uri $fallbackSerialUrl -Method Get -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
                if ($fallbackResp -and $fallbackResp.is_registered -eq $true) {
                    $foundBySerial = $true
                    $response = $fallbackResp
                    Write-Host ""
                    Write-Host "[i] Uredjaj pronadjen po serijskom broju ($TargetSerial) sa oznakom '$($response.device_tag)'!" -ForegroundColor Green
                    Write-Host "    Povezujem prethodnu servisnu istoriju sa centralnog Servis Hub-a..." -ForegroundColor Cyan
                    if ($TargetFolder) {
                        Export-HubHistoryMarkdown -History $response -TargetFolder $TargetFolder
                        Merge-HubDnevnik -History $response -TargetFolder $TargetFolder
                    }
                }
            } catch {}
        }

        if (-not $foundBySerial) {
            Write-Host ""
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host "  SERVIS HUB EVIDENCIJA: NOVI UREDJAJ                             " -ForegroundColor Yellow
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host "  [i] Uredjaj se prvi put evidentira na ServisHub-u." -ForegroundColor Green
            Write-Host "      Nema prethodne servisne istorije u centralnoj radionickoj bazi." -ForegroundColor Gray
            Write-Host "==================================================================" -ForegroundColor Cyan
            Write-Host ""
        }
    }

    return $response
}

function Invoke-HubRegister {
    param (
        [string]$TargetHubUrl,
        [string]$TargetDeviceTag,
        [string]$TargetSerial,
        [string]$TargetFolder,
        [string]$Status = "U_DIJAGNOSTICI",
        [string]$PendingDir
    )

    if (-not $TargetDeviceTag -and $TargetFolder) {
        $hw = Get-HardwareProfile -DeviceDirPath $TargetFolder
        $TargetDeviceTag = if ($hw.tag) { $hw.tag } else { Split-Path $TargetFolder -Leaf }
        if (-not $TargetSerial -and $hw.serial -ne "UNKNOWN") {
            $TargetSerial = $hw.serial
        }
    }

    $hwProfile = if ($TargetFolder) { Get-HardwareProfile -DeviceDirPath $TargetFolder } else { @{} }
    $effectiveSerial = if ($TargetSerial) { $TargetSerial } elseif ($hwProfile.serial) { $hwProfile.serial } else { "UNKNOWN" }
    $serviserId = if ($env:SERVISER_ID) { $env:SERVISER_ID } else { "USB_TEREN_01" }
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $regPayload = [ordered]@{
        device_tag    = $TargetDeviceTag
        serial_number = $effectiveSerial
        status        = $Status
        serviser_id   = $serviserId
        timestamp     = $timestamp
        hardware      = [ordered]@{
            manufacturer  = $hwProfile.manufacturer
            model         = $hwProfile.model
            cpu           = $hwProfile.cpu
            ram_gb        = $hwProfile.ram_gb
            disks         = $hwProfile.disks
            os            = $hwProfile.os
            bios          = $hwProfile.bios
            serial_number = $effectiveSerial
        }
    }

    $jsonPayload = $regPayload | ConvertTo-Json -Depth 5
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
    $encodedTag = [System.Uri]::EscapeDataString($TargetDeviceTag)
    $regUrl = "$TargetHubUrl/api/devices/$encodedTag/register"

    Write-Host "[*] Pre-flight registracija novog uredjaja na Servis Hub-u..." -ForegroundColor Cyan
    Write-Host "    Destinacija: $regUrl" -ForegroundColor DarkGray

    try {
        $resp = Invoke-RestMethod -Uri $regUrl -Method Post -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        Write-Host "[OK] Novi servisni karton uspesno otvoren na Servis Hub-u (Status: $Status)." -ForegroundColor Green
        return [PSCustomObject]@{
            Success    = $true
            SentOnline = $true
            DeviceTag  = $TargetDeviceTag
            Action     = $resp.action
        }
    } catch {
        Write-Host "[!] Servis Hub nije dostupan za registraciju ($($_.Exception.Message))." -ForegroundColor Yellow
        Write-Host "[*] Cuvanje registracije u lokalni red cekanja (offline queue)..." -ForegroundColor Yellow

        $fileTimestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $safeTag = ($TargetDeviceTag -replace '[^\w\-]', '_')
        $queueFileName = "${fileTimestamp}_REGISTER_${safeTag}.json"
        $queueFilePath = Join-Path $PendingDir $queueFileName

        try {
            [System.IO.File]::WriteAllText($queueFilePath, $jsonPayload, [System.Text.Encoding]::UTF8)
            Write-Host "[OK] Registracioni paket sacuvan u: pending_sync/$queueFileName" -ForegroundColor Cyan
        } catch {
            Write-Host "[X] GRESKA pri upisu u offline red: $($_.Exception.Message)" -ForegroundColor Red
        }

        return [PSCustomObject]@{
            Success    = $true
            SentOnline = $false
            DeviceTag  = $TargetDeviceTag
            Action     = "queued"
        }
    }
}

function Invoke-HubCheckpoint {
    param (
        [string]$TargetHubUrl,
        [string]$TargetDeviceTag,
        [string]$TargetSerial,
        [string]$TargetFolder,
        [string]$Summary,
        [string]$Status = "U_DIJAGNOSTICI",
        [string[]]$ToolsExecuted = @(),
        [string]$PendingDir
    )

    if (-not $TargetDeviceTag -and $TargetFolder) {
        $hw = Get-HardwareProfile -DeviceDirPath $TargetFolder
        $TargetDeviceTag = if ($hw.tag) { $hw.tag } else { Split-Path $TargetFolder -Leaf }
        if (-not $TargetSerial -and $hw.serial -ne "UNKNOWN") {
            $TargetSerial = $hw.serial
        }
    }

    if (-not $Summary) {
        $Summary = "Operativni kontrolni nalaz tokom dijagnostike."
    }

    if ($TargetFolder -and (Test-Path $TargetFolder)) {
        $dnevnikPath = Join-Path $TargetFolder "SERVISNI_DNEVNIK.md"
        $tsStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $cpEntry = "### [Datum: $tsStr] - Status: $Status`n- **Kontrolna tacka (Checkpoint):** $Summary"
        if ($ToolsExecuted -and $ToolsExecuted.Count -gt 0) {
            $cpEntry += "`n- **Pokrenuti alati:** $($ToolsExecuted -join ', ')"
        }

        try {
            if (-not (Test-Path $dnevnikPath)) {
                $header = "# Servisni Dnevnik Intervencija: $TargetDeviceTag`n`nOvaj dokument sadrzi istoriju svih servisnih intervencija i dijagnostickih nalaza za ovaj racunar.`n`n---`n`n"
                [System.IO.File]::WriteAllText($dnevnikPath, $header + $cpEntry + "`n", [System.Text.Encoding]::UTF8)
            } else {
                [System.IO.File]::AppendAllText($dnevnikPath, "`n`n$cpEntry`n", [System.Text.Encoding]::UTF8)
            }
            Write-Host "[OK] Checkpoint zabelezen u lokalni servisni dnevnik." -ForegroundColor Green
        } catch {
            Write-Host "[!] Upozorenje pri upisu u lokalni dnevnik: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $checkpointId = [guid]::NewGuid().ToString()
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $serviserId = if ($env:SERVISER_ID) { $env:SERVISER_ID } else { "USB_TEREN_01" }

    $cpPayload = [ordered]@{
        device_tag     = $TargetDeviceTag
        serial_number  = $TargetSerial
        checkpoint_id  = $checkpointId
        timestamp      = $timestamp
        summary        = $Summary
        status         = $Status
        tools_executed = $ToolsExecuted
        serviser_id    = $serviserId
    }

    $jsonPayload = $cpPayload | ConvertTo-Json -Depth 5
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
    $encodedTag = [System.Uri]::EscapeDataString($TargetDeviceTag)
    $cpUrl = "$TargetHubUrl/api/devices/$encodedTag/checkpoint"

    Write-Host "[*] Slanje checkpoint-a na Servis Hub..." -ForegroundColor Cyan

    try {
        $resp = Invoke-RestMethod -Uri $cpUrl -Method Post -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        Write-Host "[OK] Checkpoint uspesno poslat na Servis Hub (Status: $Status)." -ForegroundColor Green
        return [PSCustomObject]@{
            Success      = $true
            SentOnline   = $true
            DeviceTag    = $TargetDeviceTag
            CheckpointId = $checkpointId
        }
    } catch {
        Write-Host "[!] Slanje checkpoint-a na Servis Hub nije uspelo ($($_.Exception.Message))." -ForegroundColor Yellow
        Write-Host "[*] Cuvanje checkpoint-a u offline red cekanja..." -ForegroundColor Yellow

        $fileTimestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $safeTag = ($TargetDeviceTag -replace '[^\w\-]', '_')
        $queueFileName = "${fileTimestamp}_CHECKPOINT_${safeTag}.json"
        $queueFilePath = Join-Path $PendingDir $queueFileName

        try {
            [System.IO.File]::WriteAllText($queueFilePath, $jsonPayload, [System.Text.Encoding]::UTF8)
            Write-Host "[OK] Checkpoint sacuvan u red cekanja: pending_sync/$queueFileName" -ForegroundColor Cyan
        } catch {}

        return [PSCustomObject]@{
            Success      = $true
            SentOnline   = $false
            DeviceTag    = $TargetDeviceTag
            CheckpointId = $checkpointId
        }
    }
}

function Invoke-HubFlushPending {
    param (
        [string]$TargetHubUrl,
        [string]$PendingDir
    )

    if (-not (Test-Path $PendingDir)) { return }

    $pendingFiles = Get-ChildItem (Join-Path $PendingDir "*.json") -ErrorAction SilentlyContinue | Sort-Object CreationTime
    if (-not $pendingFiles -or $pendingFiles.Count -eq 0) {
        return
    }

    Write-Host "[*] Provera offline reda cekanja (pending_sync/): Pronadjeno $($pendingFiles.Count) zaostalih paketa." -ForegroundColor Yellow

    foreach ($file in $pendingFiles) {
        try {
            $jsonText = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop

            $targetTag = if ($parsed.device_tag) { $parsed.device_tag } else {
                ($file.BaseName -split "_", 3)[-1]
            }

            if (-not $targetTag) {
                Write-Host "  [!] Neispravan fajl u redu cekanja: $($file.Name) - preskacem." -ForegroundColor Yellow
                continue
            }

            $encodedTag = [System.Uri]::EscapeDataString($targetTag)
            $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonText)

            if ($file.Name -match '_REGISTER_') {
                $pushUrl = "$TargetHubUrl/api/devices/$encodedTag/register"
            } elseif ($file.Name -match '_CHECKPOINT_') {
                $pushUrl = "$TargetHubUrl/api/devices/$encodedTag/checkpoint"
            } else {
                $pushUrl = "$TargetHubUrl/api/devices/$encodedTag/agy-session"
            }

            $resp = Invoke-RestMethod -Uri $pushUrl -Method Post -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop

            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Sinhronizovano i uklonjeno iz reda cekanja: $($file.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [!] Neuspesno slanje za $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "      Prekidam praznjenje reda cekanja dok se veza sa ServisHub-om ne stabilizuje." -ForegroundColor Yellow
            break
        }
    }
}

function Invoke-HubPush {
    param (
        [string]$TargetHubUrl,
        [string]$TargetDeviceTag,
        [string]$TargetSerial,
        [string]$TargetFolder,
        [string]$PendingDir
    )

    if (-not $TargetFolder -or -not (Test-Path $TargetFolder)) {
        Write-Host "[X] GRESKA: Za -Push je obavezan validan parametar -DeviceFolder!" -ForegroundColor Red
        return $null
    }

    $resolvedFolder = (Resolve-Path $TargetFolder -ErrorAction SilentlyContinue).Path
    if ($resolvedFolder) { $TargetFolder = $resolvedFolder }

    $hw = Get-HardwareProfile -DeviceDirPath $TargetFolder
    $effectiveTag = if ($TargetDeviceTag) { $TargetDeviceTag } elseif ($hw.tag) { $hw.tag } else { Split-Path $TargetFolder -Leaf }
    $effectiveSerial = if ($TargetSerial) { $TargetSerial } elseif ($hw.serial) { $hw.serial } else { "UNKNOWN" }

    $dnevnikEntry = Get-LatestDnevnikEntry -DeviceDirPath $TargetFolder
    $diagData = Get-DiagnosticReportData -DeviceDirPath $TargetFolder

    $summary = if ($diagData.summary) {
        $diagData.summary
    } elseif ($dnevnikEntry) {
        "Servisna sesija za $effectiveTag"
    } else {
        "Zavrsena servisna sesija bez zabelezenih anomalija."
    }

    $status = $diagData.status
    $tools = $diagData.tools
    if ($tools.Count -eq 0 -and $dnevnikEntry) {
        $mTools = [regex]::Matches($dnevnikEntry, '(?i)(Get-\w+|Test-\w+|Find-\w+|Protect-\w+)\.ps1')
        foreach ($mt in $mTools) {
            if ($tools -notcontains $mt.Value) { $tools += $mt.Value }
        }
    }

    $sessionId = [guid]::NewGuid().ToString()
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $serviserId = if ($env:SERVISER_ID) { $env:SERVISER_ID } else { "USB_TEREN_01" }

    $sessionPayload = [ordered]@{
        device_tag      = $effectiveTag
        serial_number   = $effectiveSerial
        session_id      = $sessionId
        timestamp       = $timestamp
        serviser_id     = $serviserId
        hardware        = [ordered]@{
            manufacturer = $hw.manufacturer
            model        = $hw.model
            cpu          = $hw.cpu
            ram_gb       = $hw.ram_gb
            disks        = $hw.disks
            os           = $hw.os
            bios         = $hw.bios
        }
        summary         = $summary
        status          = $status
        tools_executed  = $tools
        dnevnik_entry   = $dnevnikEntry
        report_markdown = $diagData.report_markdown
    }

    $jsonPayload = $sessionPayload | ConvertTo-Json -Depth 10
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)

    $encodedTag = [System.Uri]::EscapeDataString($effectiveTag)
    $pushUrl = "$TargetHubUrl/api/devices/$encodedTag/agy-session"

    Write-Host "[*] Slanje servisne sesije na ServisHub..." -ForegroundColor Cyan
    Write-Host "    Destinacija: $pushUrl" -ForegroundColor DarkGray

    $sentOnline = $false
    try {
        $resp = Invoke-RestMethod -Uri $pushUrl -Method Post -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        $sentOnline = $true
        Write-Host "[OK] Servisna sesija uspesno arhivirana na ServisHub ($TargetHubUrl)." -ForegroundColor Green
    } catch {
        $sentOnline = $false
        Write-Host "[!] Slanje na ServisHub nije uspelo: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "[*] Cuvanje sesije u lokalni red cekanja (offline queue)..." -ForegroundColor Yellow

        $fileTimestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $safeTag = ($effectiveTag -replace '[^\w\-]', '_')
        $queueFileName = "${fileTimestamp}_${safeTag}.json"
        $queueFilePath = Join-Path $PendingDir $queueFileName

        try {
            [System.IO.File]::WriteAllText($queueFilePath, $jsonPayload, [System.Text.Encoding]::UTF8)
            Write-Host "[OK] Sesija sacuvana u red cekanja: pending_sync/$queueFileName" -ForegroundColor Cyan
            Write-Host "     Bice automatski sinhronizovana pri sledecoj uspesnoj vezi sa ServisHub-om." -ForegroundColor Gray
        } catch {
            Write-Host "[X] GRESKA pri upisu u offline red: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Ako je slanje uspelo, odmah pokusavamo praznjenje eventualnih prethodnih zaostalih sesija
    if ($sentOnline) {
        Invoke-HubFlushPending -TargetHubUrl $TargetHubUrl -PendingDir $PendingDir
    }

    return [PSCustomObject]@{
        Success    = $true
        SentOnline = $sentOnline
        DeviceTag  = $effectiveTag
        SessionId  = $sessionId
    }
}

# -----------------------------------------------------------------------------
# 5. GLAVNI TOK IZVRSAVANJA
# -----------------------------------------------------------------------------

$usbRoot = Get-UsbRoot
$pendingDir = Get-PendingQueueDir -RootPath $usbRoot
$effectiveHubUrl = Resolve-HubUrl -ExplicitUrl $HubUrl -RootPath $usbRoot

# Rutiranje po parametrima
if ($Pull) {
    Invoke-HubPull -TargetHubUrl $effectiveHubUrl `
                   -TargetDeviceTag $DeviceTag `
                   -TargetSerial $SerialNumber `
                   -TargetFolder $DeviceFolder
} elseif ($Push) {
    Invoke-HubPush -TargetHubUrl $effectiveHubUrl `
                   -TargetDeviceTag $DeviceTag `
                   -TargetSerial $SerialNumber `
                   -TargetFolder $DeviceFolder `
                   -PendingDir $pendingDir
} elseif ($Register) {
    Invoke-HubRegister -TargetHubUrl $effectiveHubUrl `
                       -TargetDeviceTag $DeviceTag `
                       -TargetSerial $SerialNumber `
                       -TargetFolder $DeviceFolder `
                       -Status (if ($Status) { $Status } else { "U_DIJAGNOSTICI" }) `
                       -PendingDir $pendingDir
} elseif ($Checkpoint) {
    Invoke-HubCheckpoint -TargetHubUrl $effectiveHubUrl `
                         -TargetDeviceTag $DeviceTag `
                         -TargetSerial $SerialNumber `
                         -TargetFolder $DeviceFolder `
                         -Summary $Summary `
                         -Status (if ($Status) { $Status } else { "U_DIJAGNOSTICI" }) `
                         -ToolsExecuted $ToolsExecuted `
                         -PendingDir $pendingDir
} elseif ($FlushPending) {
    Write-Host "[*] Pokrecem rucno praznjenje offline reda cekanja na: $effectiveHubUrl" -ForegroundColor Cyan
    Invoke-HubFlushPending -TargetHubUrl $effectiveHubUrl -PendingDir $pendingDir
} else {
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "          SINHRONIZACIJA SA SERVIS HUB-OM (ADR-0003 / ADR-0004)   " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "Aktivni ServisHub URL: $effectiveHubUrl" -ForegroundColor White
    Write-Host "Offline red cekanja:  $pendingDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Upotreba:" -ForegroundColor Yellow
    Write-Host "  .\scripts\Sync-ServiceHub.ps1 -Pull -DeviceTag <Tag> [-SerialNumber <SN>]" -ForegroundColor White
    Write-Host "  .\scripts\Sync-ServiceHub.ps1 -Register -DeviceFolder <Path> [-Status <Status>]" -ForegroundColor White
    Write-Host "  .\scripts\Sync-ServiceHub.ps1 -Checkpoint -DeviceFolder <Path> -Summary <Text> [-Status <Status>]" -ForegroundColor White
    Write-Host "  .\scripts\Sync-ServiceHub.ps1 -Push -DeviceFolder <Path>" -ForegroundColor White
    Write-Host "  .\scripts\Sync-ServiceHub.ps1 -FlushPending" -ForegroundColor White
    Write-Host "==================================================================" -ForegroundColor Cyan
}
