---
name: event-log-triage
description: Trijaža kritičnih sistemskih i aplikativnih grešaka iz Windows Event Log-a u poslednjih 24-48h, analiza neočekivanih gašenja (Kernel-Power) i hardverskih incidenata (WHEA).
---

# Veština: Trijaža Windows Dnevnika Događaja (event-log-triage)

Ova veština omogućava filtriranje i korelaciju kritičnih događaja koji ukazuju na hardversku nestabilnost ili softverske padove.

## Kada koristiti ovu veštinu:
- Računar se sam gasi, zamrzava ili restartuje bez plavog ekrana.
- Potrebno je ustanoviti vremensku hronologiju događaja pre rušenja sistema.
- Serviser traži proveru logova, Kernel-Power analizu ili pregled grešaka u poslednja 24-48h.

## Koraci izvršavanja:

1. **Pokretanje dijagnostičke skripte:**
   Izvrši pripremljenu PowerShell skriptu sa vremenskim rasponom:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File ".\scripts\Get-EventLogTriage.ps1" -Hours 24
   ```
   (Po potrebi možeš povećati broj sati na 48 ili 72: `-Hours 48`).

2. **Pravila tumačenja i korelacije (Root-Cause):**
   - **Kernel-Power (Event ID 41):**
     - Oznacava da se sistem ugasio bez čistog shutdown-a.
     - *Pravilo:* Odmah pogledaj koje su greške nastupile 1-5 minuta PRE Event ID 41!
     - Ako pre toga postoje `storahci`, `disk` ili `nvme` greške (Event ID 153/129): uzrok je prekid komunikacije sa diskom.
     - Ako nema prethodnih grešaka i BugcheckCode je 0: uzrok je prekid napajanja (neispravan adapter, napajanje, nestanak struje ili pregrevanje sa thermal cutoff).
   - **WHEA-Logger (Event ID 17, 18, 19, 20):**
     - Predstavlja Windows Hardware Error Architecture događaje.
     - Ukazuje na neispravan procesor (Machine Check Exception), degradirane PCIe magistrale ili problematičan RAM.
   - **Disk i NTFS (Event ID 55, 98, 153):**
     - Ukazuje na oštećenja fajl sistema ili I/O timeout kontrolera.

3. **Format izveštaja:**
   - **Vremenska linija:** Kada su počeli incidenti.
   - **Glavni osumnjičeni:** Hardver (napajanje, ploča, disk) ili drajver.
   - **Preporučeni test:** npr. MemTest86, test napajanja pod opterećenjem (OCCT), ili zamena I/O kabla/porta.
