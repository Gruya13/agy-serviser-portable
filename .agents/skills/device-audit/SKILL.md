---
name: device-audit
description: Automatska identifikacija hardvera, očitavanje serijskog broja (BIOS/Matična ploča/UUID), modela računara i upravljanje servisnim kartonom (DEVICE_INFO.md).
---

# Veština: Identifikacija Uređaja i Servisni Karton (device-audit)

Ova veština omogućava AI agentu da pouzdano očita fabrički serijski broj, model matične ploče, procesor, radnu memoriju i diskove klijentskog računara, kao i da ažurira digitalni servisni karton mašine.

## Kada koristiti ovu veštinu:
- Serviser pita: "koji je ovo računar", "proveri serijski broj", "koji je model matične ploče", "prikaži specifikacije".
- Potrebno je proveriti da li je mašina ranije bila u servisu i šta je zabeleženo u servisnom dnevniku.
- Potrebno je osvežiti podatke u `DEVICE_INFO.md`.

## Koraci izvršavanja:

1. **Pokretanje skripte za identifikaciju:**
   Izvrši PowerShell skriptu za očitavanje hardvera:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "..\..\scripts\Get-DeviceInfo.ps1"
   ```
   *(Ili `.\scripts\Get-DeviceInfo.ps1` ukoliko se poziva iz korena).*

2. **Šta skripta očitava:**
   - **Serijski broj:** Proverava BIOS serijski broj, zatim serijski broj matične ploče, a za sklopljene desktop računare uzima jedinstveni hardverski UUID.
   - **Specifikacija:** Tačan naziv procesora, broj jezgara, količina i raspored RAM-a, spisak ugrađenih diskova i grafičkih kartica.
   - **Servisni karton:** Podaci se čuvaju u `DEVICE_INFO.md` i `SERVISNI_DNEVNIK.md` unutar foldera tog uređaja.

3. **Format izveštaja serviseru:**
   - **Model i Proizvođač:** npr. Lenovo ThinkPad T14 Gen 2 (ili Asus PRIME B550M-K).
   - **Serijski broj:** Tačna oznaka (npr. `PF2A1234` ili `UUID-...`).
   - **Ključni hardver:** CPU, RAM, GPU, diskovi.
   - **Istorija:** Da li je računar ranije bio na servisu i kada.
