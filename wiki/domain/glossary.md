---
title: "Rečnik Domena i Pojmovnik (Glossary)"
type: domain
created: 2026-10-09
updated: 2026-10-09
tags:
  - domain
  - glossary
  - terminology
---

# Rečnik Domena i Pojmovnik: AGY Serviser Portable

Ovaj dokument sadrži definicije stručnih i tehničkih termina koji se koriste u sistemu **AGY Serviser Portable** i pratećim servisnim procedurama.

---

### A
- **Antigravity CLI (`agy`):** Samostalni Go binarni izvršni fajl koji predstavlja terminalsko jezgro AI agenta kompanije Google/Antigravity.
- **Autorun Imunizacija (Vakcinacija):** Kreiranje zaštićenog direktorijuma `autorun.inf` sa atributima ReadOnly, Hidden i System na USB medijumu radi sprečavanja malvera da kreira zlonamerni autorun fajl.

### B
- **BSOD (Blue Screen of Death):** Kritični pad operativnog sistema Windows izazvan neotklonjivom greškom na nivou jezgra (kernel space), praćen generisanjem Crash Dump fajla.
- **BugCheck Code (Stop Code):** Heksadecimalna vrednost (npr. `0x0000007E`, `0x000000D1`) koja precizno identifikuje tip i uzrok rušenja operativnog sistema.

### C
- **CBS Log (`C:\Windows\Logs\CBS\CBS.log`):** Sistemski dnevnik operativnog sistema u koji servisi SFC i DISM upisuju detaljne podatke o stanju i popravci sistemskih biblioteka i komponentnog skladišta.
- **CIM (Common Information Model):** Savremeni WMI interfejs u PowerShell-u (`Get-CimInstance`) koji omogućava pouzdano očitavanje hardverskih informacija.

### D
- **DeviceTag:** Standardizovana, sanitizovana jedinstvena oznaka računara formirana od proizvođača, modela i serijskog broja (npr. `Dell_Inc__Latitude_5420_8G7X123`).
- **DISM (Deployment Image Servicing and Management):** Ugrađeni Windows alat za kontrolu i popravku integriteta Component Store skladišta.

### H
- **Hardware Write-Protect:** Fizički hardverski prekidač na USB memoriji koji sprečava bilo kakav upis ili modifikaciju podataka na čipu od strane operativnog sistema klijenta.
- **Headless OAuth:** Režim autorizacije gde CLI ne otvara veb pregledač na klijentu već generiše link/kod koji serviser autorizuje preko svog mobilnog telefona.

### K
- **Kernel-Power (Event ID 41):** Sistemski događaj koji beleži da je računar ugašen bez prethodne regularne shutdown procedure (nestanak napajanja, pad napona, prinudno gašenje).

### N
- **Non-Destructive Principle:** Pravilo bezbednosti po kome AI asistent nikada ne preduzima destruktivne radnje (formatiranje, brisanje podataka ili drajvera) bez eksplicitne potvrde servisera.

### O
- **Offline Queue (`pending_sync/`):** Lokalni red čekanja na USB flešu u koji se privremeno skladište JSON paketi servisnih sesija kada radionički Servis Hub server nije dostupan.

### P
- **Post-flight Push:** Automatsko pakovanje hardverskog profila, dnevnika i izveštaja na kraju sesije i njihovo slanje na Servis Hub.
- **Pre-flight Pull:** Upit koji se šalje Servis Hub-u pre početka AI sesije radi očitavanja prethodnih intervencija kolega na istoj mašini.

### R
- **Root Cause (Primarni uzrok):** Osnovni, fundamentalni uzrok kvara računara (npr. pregrevanje usled zasušene termalne paste ili oštećenje NVMe kontrolera), za razliku od pukih površnih manifestacija.

### S
- **Servis Hub:** Centralni kontrolni server u radionici koji vodi evidenciju o floti uređaja, izveštajima i servisnim intervencijama.
- **SFC (System File Checker):** Windows alat za proveru i verifikaciju integriteta zaštićenih sistemskih datoteka (`sfc /VERIFYONLY` ili `sfc /scannow`).
- **SMART (Self-Monitoring, Analysis and Reporting Technology):** Sistem praćenja zdravlja i pouzdanosti unutar čvrstih diskova i SSD uređaja.

### U
- **UDP Auto-Discovery:** Mehanizam u kome USB klijent šalje broadcast UDP paket na port 8888 kako bi automatski pronašao IP adresu i port Servis Hub servera u lokalnoj mreži.

### W
- **Wear Level:** Procenat istrošenosti fleš NAND ćelija na SSD/NVMe diskovima.
- **WHEA (Windows Hardware Error Architecture):** Arhitektura za prijavu hardverskih grešaka (WHEA-Logger Event ID 17-20) koje generiše procesor ili matična ploča.
