---
title: "ADR-0002: Hardverska Zaštita od Upisa, Separacija Radnih Prostora i Identifikacija Uređaja"
type: decision
status: accepted
created: 2026-09-10
updated: 2026-10-09
tags:
  - adr
  - decision
  - architecture
  - write-protect
  - fingerprinting
  - devices
---

# ADR-0002: Hardverska Zaštita od Upisa, Separacija Radnih Prostora i Identifikacija Uređaja

## 1. Kontekst i Problem
1. **Infekcija USB-a malverom:** Pri radu na zaraženim računarima, USB memorija može biti inficirana crvima, skrivenim skriptama i lažnim `.lnk` prečicama. Korišćenje USB memorije sa fizičkim prekidačem za zaštitu od upisa (Hardware Write-Protect) u potpunosti sprečava infekciju, ali CLI alat podrazumevano ne može da piše profil na zaključani medijum.
2. **Mešanje servisnih sesija:** Ako serviser popravlja desetine različitih računara, svi podaci, logovi i razgovori bi se gomilali u jedinstvenom profilu, otežavajući pretragu i rekonstrukciju istorije popravki.

## 2. Razmatrane Opcije
- **Opcija A: Rad isključivo na otključanom USB-u sa ručnim imenovanjem foldera:** Podložno ljudskoj grešci, ne štiti medijum od virusa.
- **Opcija B: Automatska detekcija Write-Protect statusa i automatski digitalni karton po serijskom broju [PRIHVAĆENO]:**
  - **HW Write-Protect detekcija:** Skripta testira upis na fleš; ako je medijum zaključan, radni profil se privremeno alocira u `%TEMP%\ServisAI_<GUID>` i samouništava pri gašenju.
  - **Automatski Fingerprinting:** Očitavanje serijskog broja kroz hijerarhiju BIOS -> Matična ploča -> UUID -> ComputerName.
  - **Kreiranje `devices/<DeviceTag>/`:** Svaki računar dobija sopstveni folder sa `DEVICE_INFO.md`, `SERVISNI_DNEVNIK.md` i `reports/IZVESTAJ_DIJAGNOSTIKE.md`.
  - **USB Vakcinacija:** Za otključane fleševe kreira se zaštićeni `autorun.inf` folder (ReadOnly+Hidden+System) i primenjuje auto-čišćenje pre i posle sesije.

## 3. Doneta Odluka
Implementirani su moduli:
- `scripts/Get-DeviceInfo.ps1` za pouzdanu identifikaciju hardvera i izradu kartona.
- `scripts/Protect-USBIntegrity.ps1` za vakcinaciju, kontrolu heševa (SHA-256) i automatsko uklanjanje malicioznih datoteka.
- `Start-ServisAI.ps1` orkestrira grananje između trajnog USB profila i privremenog `%TEMP%` profila.

## 4. Posledice i Status
- **Pozitivne:** Potpuna bezbednost fleša na visoko zaraženim računarima; jasna evidencija po mašinama; automatsko prepoznavanje "povratnika" u servis i opcija nastavka prethodne sesije (`agy -c`).
- **Negativne:** U Write-Protect režimu, lokalni podaci sesije se brišu sa klijenta, pa je za očuvanje nalaza neophodna sinhronizacija na Servis Hub.
