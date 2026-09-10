---
name: bsod-analyzer
description: Detaljna analiza uzroka plavog ekrana smrti (BSOD), tumačenje BugCheck kodova, analiza Minidump datoteka i identifikacija problematičnih drajvera.
---

# Veština: Analiza Plavih Ekrana (bsod-analyzer)

Ova veština analizira minidump datoteke i BugCheck događaje kako bi identifikovala tačan drajver, sistemski servis ili hardversku komponentu koja je srušila Windows.

## Kada koristiti ovu veštinu:
- Računar izbacuje plavi ekran (BSOD).
- Postoje kreirani `.dmp` fajlovi u `C:\Windows\Minidump`.
- Serviser traži analizu koda greške (npr. DPC_WATCHDOG_VIOLATION, IRQL_NOT_LESS_OR_EQUAL).

## Koraci izvršavanja:

1. **Pokretanje dijagnostičke skripte:**
   Izvrši skriptu za izveštaj o minidump fajlovima:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File ".\scripts\Get-MinidumpReport.ps1"
   ```

2. **Katalog najčešćih BugCheck kodova i uzroka:**
   - **`0x0000000A` (IRQL_NOT_LESS_OR_EQUAL):** Loš drajver pristupa nedozvoljenoj memorijskoj adresi na visokom IRQL nivou. Čest uzrok: antivirus, mrežni drajver, grafički drajver.
   - **`0x0000003B` (SYSTEM_SERVICE_EXCEPTION):** Izuzetak u radu sistemskog servisa. Često povezano sa grafičkim drajverom ili memorijskim konfliktom.
   - **`0x0000007E` (SYSTEM_THREAD_EXCEPTION_NOT_HANDLED):** Sistemska nit je doživela neobrađen izuzetak. Gotovo uvek ukazuje na specifičan `.sys` drajver naveden u logu.
   - **`0x0000009F` (DRIVER_POWER_STATE_FAILURE):** Drajver ne uspeva da pređe u stanje spavanja ili buđenja (sleep/wake). Čest uzrok: drajveri za čipset, Wi-Fi ili Bluetooth.
   - **`0x00000124` (WHEA_UNCORRECTABLE_ERROR):** Čist hardverski otkaz procesora, radne memorije ili PCIe sabirnice (neispravan napon, pregrevanje, degradacija jezgara).
   - **`0x00000133` (DPC_WATCHDOG_VIOLATION):** DPC rutina je prekoračila vremenski limit. Tipično kod starih SSD drajvera (storahci vs iaStorAC) ili bežičnih mrežnih kartica.

3. **Format izveštaja serviseru:**
   - **Kôd greške:** Heksadecimalna vrednost i naziv (npr. `0x133 DPC_WATCHDOG_VIOLATION`).
   - **Odgovorni modul/drajver:** npr. `nvlddmkm.sys`, `rtwlanu.sys`, `ntoskrnl.exe`.
   - **Verovatnoća (Hardver vs Drajver):** Procenti verovatnoće.
   - **Konkretan korak za servisera:** (npr. "Deinstalirati GeForce drajver pomoću DDU u Safe Mode-u i instalirati WHQL verziju").
