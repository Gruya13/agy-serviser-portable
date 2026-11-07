---
title: "Evidencija Zamki, Bagova i Rešenja (Gotchas & Workarounds)"
type: memory
created: 2026-10-09
updated: 2026-10-09
tags:
  - memory
  - gotchas
  - bugs
  - troubleshooting
---

# Evidencija Zamki, Bagova i Rešenja (Gotchas)

Ovaj dokument sadrži evidenciju specifičnih tehničkih problema, nepredviđenih bagova i načina njihovog trajnog rešavanja u okviru projekta **AGY Serviser Portable**.

---

## 1. Conhost Buffer Glitch (Preskakanje 20-30 redova u Windows konzoli)
- **Simptom:** Pri svakom odgovoru AI modela, Windows terminal (`conhost.exe`) umeće 20 do 30 praznih redova, uzrokujući da tekst odleti sa ekrana.
- **Uzrok:** Neslaganje između širine prozora (`WindowSize.Width`) i širine virtuelnog bafera (`BufferSize.Width`). Pri automatskom prelomu redova (word wrap), conhost dodaje praznine do pune širine bafera.
- **Rešenje:** U `Start-ServisAI.ps1` striktno zaključavamo širinu bafera na širinu prozora, a visinu uvećavamo na 9000 linija:
  ```powershell
  $raw.BufferSize = New-Object System.Management.Automation.Host.Size($raw.BufferSize.Width, 9000)
  ```
  Takođe se postavljaju `TERM="xterm-256color"` i `PAGER="cat"`.

---

## 2. CMD Crash pri pozivanju `chcp 65001` unutar `.bat` fajla
- **Simptom:** Pokretanje `Start-ServisAI.bat` dvoklikom momentalno ruši prozor bez ikakve poruke o grešci na pojedinim verzijama Windows 10.
- **Uzrok:** Pozivanje `chcp 65001` (prelazak na UTF-8 kodnu stranicu) u standardnom `cmd.exe` interpretatoru izaziva prekid interpretacije tekućeg batch skripta (buffer reload bug u cmd.exe).
- **Rešenje:** Uklonjen `chcp 65001` iz `.bat` fajla. Kodiranje se podešava isključivo unutar PowerShell-a preko `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`. Takođe, u batch fajl je ugrađen `-NoExit` osigurač.

---

## 3. Generički i Prazni BIOS Serijski Brojevi na Sklopljenim Konfiguracijama
- **Simptom:** `Win32_Bios.SerialNumber` vraća vrednosti poput `To be filled by O.E.M.`, `Default string`, `None`, `00000000` ili prazan string.
- **Uzrok:** Proizvođači jeftinijih matičnih ploča ne upisuju specifičan serijski broj u DMI/SMBIOS tabelu.
- **Rešenje:** Uveden višeslojni regex filter u `scripts/Get-DeviceInfo.ps1`. Ako je BIOS serijski broj generički, algoritam automatski prelazi na serijski broj matične ploče (`Win32_BaseBoard.SerialNumber`), hardverski UUID čipa (`Win32_ComputerSystemProduct.UUID`) ili fallback na naziv računara (`PC-COMPUTERNAME`).

---

## 4. Ograničenja Zaključanog USB-a (Hardware Write-Protect)
- **Simptom:** Kada se koristi USB fleš sa fizičkim prekidačem za zaštitu od upisa, `agy.exe` puca jer pokušava da kreira profil u `data/` folderu na USB-u.
- **Uzrok:** Operativni sistem odbija svaki pokušaj upisa na fleš disk na nivou kontrolera.
- **Rešenje:** `Start-ServisAI.ps1` vrši pre-flight test upisa. Ako operacija ne uspe, radni profil se preusmerava u `%TEMP%\ServisAI_<GUID>` na klijentskom disku. Pri završetku sesije, privremeni profil se nepovratno briše sa klijenta.

---

## 5. Mrežna Izolovanost na Terenu i Offline Sinhronizacija
- **Simptom:** Ako se računar servisira na terenu van lokalne mreže radionice, `Sync-ServiceHub.ps1` ne može da dohvati Servis Hub.
- **Uzrok:** Hub je u LAN-u radionice, a serviser je van dometa.
- **Rešenje:** Implementiran offline red čekanja (`pending_sync/`). Skripta hvata grešku konekcije, pakuje JSON sesiju u red čekanja, a pri prvoj uspešnoj sesiji u radionici automatski prazni red na Hub (`Invoke-HubFlushPending`).
