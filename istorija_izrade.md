# Istorija izrade i izmena - Antigravity CLI Portable

Ovaj dokument sadrži hronološki pregled svih implementacija, refaktorisanja i ispravki na projektu **Antigravity CLI Portable Servisni Asistent**.

---

### [2026-09-10 15:51] - Inicijalizacija projekta i uspostavljanje arhitekture
- **Smernice:** Kreiran dokument `second_brain/AI_Agent_Guidelines.md` sa standardima ponašanja, bezbednosnim protokolima i inženjerskim pravilima za servisnog agenta.
- **Evidencija:** Inicijalizovan `istorija_izrade.md` za praćenje svih promena.
- **Koncept:** Usvojen plan implementacije prenosivog Antigravity CLI asistenta za Windows (fokus na Windows 10/11 bez WinPE komponente u prvoj fazi).

### [2026-09-10 15:53] - Kompletna implementacija prenosivog servisnog sistema
- **Pokretački mehanizam:**
  - `Start-ServisAI.bat`: Realizovan starter sa automatskom UAC elevacijom (`RunAs Administrator`) i pozivanjem PowerShell-a.
  - `Start-ServisAI.ps1`: Implementiran glavni orkestrator sa mrežnom proverom Google servisa, automatskom detekcijom Hardware Write-Protect USB medijuma (preusmeravanje u `%TEMP%` i izolacija), headless OAuth zaštitom preko telefona i automatskim čišćenjem i odjavom (`/logout`) po zatvaranju sesije.
- **Konfiguracija i uloga agenta:**
  - `AGENTS.md`: Kreiran glavni sistemski prompt za Root-Cause dijagnostiku i strogo ne-destruktivno ponašanje u servisu.
  - `config/settings.json`: Postavljeni podrazumevani model (`gemini-2.5-pro`) i servisna podešavanja.
  - `bin/README_BIN.md`: Kreirano uputstvo za postavljanje `agy.exe` Windows binarnog fajla na USB.
- **PowerShell dijagnostičke skripte (`scripts/`):**
  - `Get-DiskHealth.ps1`: SMART i NVMe dijagnostika, radni vek, greške i temperature.
  - `Get-EventLogTriage.ps1`: Trijaža kritičnih Kernel-Power, WHEA i Disk padova u System i Application logovima.
  - `Get-MinidumpReport.ps1`: Analiza BSOD rušenja, Stop kodova i oštećenih drajvera.
  - `Test-SystemIntegrity.ps1`: Bezbedna provera integriteta sistemskih datoteka preko SFC i DISM.
  - `Find-SuspiciousAutoruns.ps1`: Detekcija sumnjivih autorun unosa, skripti u Temp/AppData i perzistencije malvera.
- **Servisne veštine (`.agents/skills/` i `skills/`):**
  - Implementirane veštine: `smart-health`, `event-log-triage`, `bsod-analyzer`, `system-integrity`, `malware-triage`.
- **Dokumentacija i verifikacija:**
  - Kreiran `README.md` sa detaljnim koracima pripreme i korišćenja USB alata.
  - Konfigurisan `.gitignore` radi zaštite sesija, keša i tokena.

### [2026-09-10 16:04] - Implementacija USB samozaštite, imunizacije i trajne prijave
- **Trajna prijava na otključanom flešu:**
  - Ažuriran `Start-ServisAI.ps1` tako da ne vrši automatsku odjavu kada se koristi `data/` profil na USB-u. Serviser se prijavljuje samo jednom, a na narednim klijentskim mašinama CLI odmah startuje bez verifikacije telefonom.
- **USB samoodbrana i auto-čišćenje (`Protect-USBIntegrity.ps1`):**
  - Implementirana skripta za automatsko otkrivanje i brisanje USB crva, lažnih `.lnk` prečica, `.vbs` skripti i zalutalih `.exe` datoteka.
  - Ugrađena USB vakcinacija (zaštićen `autorun.inf` direktorijum sa blokiranim atributima).
  - Mehanizam heš provere (SHA-256) ključnih fajlova protiv modifikacija.
- **Integracija u pokretač i veštine:**
  - `Start-ServisAI.ps1` automatski pokreće imunizaciju i čišćenje pre starta i nakon završetka svake dijagnostičke sesije.
  - Kreirana nova veština `usb-defense` u `.agents/skills/usb-defense/` i `skills/usb-defense/`, a `AGENTS.md` je proširen ovom komandom.


