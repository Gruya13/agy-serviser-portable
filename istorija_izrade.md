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

### [2026-09-10 16:05] - Izrada sveobuhvatnog servisnog priručnika (UPUTSTVO_ZA_KORISCENJE.md)
- **Kompletan priručnik u Markdown formatu:**
  - Kreiran fajl `UPUTSTVO_ZA_KORISCENJE.md` koji detaljno objašnjava arhitekturu, jednokratnu pripremu USB diska, preuzimanje i postavljanje `agy.exe`, jednokratnu trajnu prijavu preko telefona, proceduru pokretanja na klijentskim mašinama, katalog svih 6 servisnih veština sa primerima upita, USB samoodbranu i rešavanje problema (troubleshooting).

### [2026-09-10 19:24] - Implementacija detekcije uređaja po serijskom broju i odvajanje četova po mašinama
- **Automatska identifikacija klijentskog računara (`Get-DeviceInfo.ps1`):**
  - Implementirano automatsko očitavanje serijskog broja iz BIOS-a (za brendirane laptopove/desktop mašine), matične ploče (za desktop računare) i hardverskog UUID-a kao fallback mehanizma.
  - Očitavanje kompletne hardverske specifikacije (CPU, RAM, GPU, diskovi, OS).
- **Servisni kartoni i odvajanje sesija (`devices/<DeviceTag>/`):**
  - Automatsko kreiranje foldera za svaki pojedinačni računar sa `DEVICE_INFO.md` i `SERVISNI_DNEVNIK.md`.
  - Odvajanje radnog prostora i četova po mašinama – svaka mašina ima svoju istoriju i konverzacije.
  - Zadržavanje deljenog login tokena u `data/` tako da se ne zahteva ponovna autorizacija telefonom.
- **Upravljanje povratnicima u servisu:**
  - `Start-ServisAI.ps1` detektuje da li je računar već bio na servisu i nudi meni: nastavak prethodnog razgovora (`agy -c`) ili nova servisna sesija.
- **Nova veština `device-audit` i ažuriranje `AGENTS.md`:**
  - Dodata veština za analizu i osvežavanje hardverske karte računara.

### [2026-09-10 19:27] - Otklanjanje problema sa preskakanjem redova u konzoli (Terminal Buffer Glitch)
- **Konzolna i bafer optimizacija (`Start-ServisAI.ps1` i `Start-ServisAI.bat`):**
  - Implementirana striktna sinhronizacija `BufferSize.Width = WindowSize.Width` i uvećanje visine bafera na 9000 linija. Ovo eliminiše bag gde conhost umeće 20-30 praznih linija usled nepoklapanja širine prozora i bafera.
  - Postavljeno UTF-8 kodiranje (`[Console]::OutputEncoding`, `chcp 65001`), `TERM=xterm-256color` i `PAGER=cat`.
- **Ažuriranje `AGENTS.md` (Pravilo kompaktnosti i snimanja izveštaja):**
  - Definisano pravilo da agent ne šalje višestruke prazne linije i da svaki kompletan dijagnostički izveštaj automatski sačuva u `reports\IZVESTAJ_DIJAGNOSTIKE.md` na USB-u, a serviseru prikaže jasan sažetak u konzoli.

### [2026-09-10 19:35] - Ispravka naglog zatvaranja prozora (Fix CMD Crash i UAC NoExit osigurač)
- **Uzrok baga:** Poziv `chcp 65001` unutar samog `.bat` fajla je u Windows CMD-u izazivao prekid parsiranja skripte i naglo gašenje konzole.
- **Ispravka `Start-ServisAI.bat`:**
  - Uklonjen `chcp` iz batch fajla (UTF-8 se postavlja bezbedno unutar PowerShell-a).
  - Dodat `-NoExit` osigurač za PowerShell koji onemogućava samovoljno zatvaranje prozora čak i ako skripta naiđe na prekid.
- **Ispravka `Start-ServisAI.ps1`:**
  - Zadržan radni direktorijum u korenu alata (`$scriptDir`) sa dodavanjem foldera uređaja preko `--add-dir`, kako bi `agy` uvek video `config/settings.json` i veštine.
  - Zaštićen opcioni nastavak sesije (`-c`) markerom `.has_session` kako se CLI ne bi rušio ako prethodna sesija ne postoji.

### [2026-10-09 16:15] - Implementacija dvosmerne sinhronizacije servisne istorije sa centralnim Servis Hub-om (ADR-0003)
- **Koncept i Arhitektura (ADR-0003):**
  - Uspostavljena dvosmerna integracija između prenosivog asistenta na USB medijumu i centralnog radioničkog servera Servis Hub.
  - Eliminisana izolovanost nalaza na pojedinačnom flešu: prenos servisne istorije omogućava serviserima uvid u prethodne kvarove i intervencije kolega na istom računaru.
- **Implementacija na Servis Hub-u (`Servis Hub`):**
  - `servishub/reports.py`: Implementirane metode `save_agy_session()` i `get_device_history()` za perzistenciju sesija u `storage/reports/<DeviceTag>/sessions/`, automatsko ažuriranje `DEVICE_INFO.json` profila i kumulativno dopunjavanje centralnog `SERVISNI_DNEVNIK.md`.
  - `servishub/handlers.py`: Dodate REST API rute `GET /api/devices/{tag}/history` (i pretraga po serijskom broju `GET /api/devices/by-serial/{serial}/history`) za Pre-flight očitavanje istorije, i `POST /api/devices/{tag}/agy-session` za Post-flight prijem završene dijagnostičke sesije.
  - `servishub/telemetry.py`: Prošireno upravljanje flotom računara (`FleetStore`) gde se servisirani uređaji automatski registruju i osvežavaju sa statusom `"Servisiran (AGY)"` ili `"Kvar (AGY)"` uz direktan uvid u nalaze na Web Dashboard-u.
  - `tests/test_agy_sync_api.py`: Integracioni testovi za kompletnu pokrivenost novih ruta, validaciju JSON tela i kumulativno dopunjavanje dnevnika.
- **Implementacija na AGY Serviseru (`AGY Serviser Portable`):**
  - `scripts/Sync-ServiceHub.ps1`: Glavni PowerShell klijentski modul sa:
    - UDP Auto-Discovery pretragom Servis Hub-a na portu 8888 (`Find-ServisHubUdp`) i automatskim prelaskom na statički URL (`Resolve-HubUrl`).
    - Pre-flight Pull mehanizmom (`-Pull`) za očitavanje i formatiran prikaz istorije u terminalu pre ulaska u asistenta.
    - Post-flight Push mehanizmom (`-Push`) za automatsko pakovanje hardverskog profila, dnevnika i izveštaja po završetku sesije.
    - Offline redom čekanja (`pending_sync/`) i mehanizmom pražnjenja (`-FlushPending`) pri ponovnom uspostavljanju veze.
  - `Start-ServisAI.ps1`:
    - Integrisana Pre-flight provera pre pokretanja CLI-ja (postavljanje varijable okruženja `$env:SERVIS_HUB_HISTORY_AVAILABLE = "true"` ako računar ima prethodnih zapisa).
    - Integrisan Post-flight Push u `finally` bloku orkestratora po završetku sesije.
  - `config/settings.json`: Dodat konfiguracioni blok `servis_hub` (`auto_discovery: true`, `discovery_port: 8888`, `static_url: "http://localhost:8000"`).
  - `tests/test_e2e_sync.py`: Sveobuhvatni E2E integracioni testovi (Scenario 1: Online životni ciklus, Scenario 2: Offline queuing, Scenario 3: Flush offline reda, višestruke sesije i otpornost na greške).
  - `tests/test_sync.ps1`: PowerShell testna skripta za verifikaciju klijentske skripte `Sync-ServiceHub.ps1`.
- **Verifikacija i QA test faza:**
  - QA test faza uspešno završena sa 100% prolaznošću:
    - **Servis Hub:** 32/32 testa uspešno prošlo (`python3 -m unittest discover -s tests -p "test_*.py"`).
    - **AGY Serviser:** 6/6 E2E integracionih scenarija uspešno prošlo (`python3 -m unittest tests/test_e2e_sync.py`).
- **Dokumentacija (Documentation Gate):**
  - Ažuriran `AGENTS.md` (sekcije 4 i 5) sa uputstvima za rad sa Servis Hub istorijom i skriptom `Sync-ServiceHub.ps1`.
  - Proširen `UPUTSTVO_ZA_KORISCENJE.md` novom sekcijom 8 posvećenom Servis Hub integraciji, auto-discovery mehanizmu i offline radu.
  - Ažuriran `README.md` sa novom stavkom u ključnim mogućnostima i dopunjenim stablom USB diska.

### [2026-10-09 19:15] - Izrada sveobuhvatne tehničke dokumentacije i lokalne Obsidian memorije
- **Kompletna tehnička dokumentacija (`TEHNICKA_DOKUMENTACIJA.md`):**
  - Izrađen sveobuhvatni inženjerski referentni priručnik (11 poglavlja) sa detaljnim opisom arhitekture, podsistema, bezbednosti, Zero-Trust autorizacije, CIM fingerprinting algoritma, dijagnostičkih skripti, kataloga veština, ADR-0003 protokola sinhronizacije (UDP :8888, REST, Offline queue), QA testova i operativnog runbook-a.
  - Integrisani detaljni Mermaid dijagrami arhitekture, životnog ciklusa sesije, detekcije serijskih brojeva i mrežne sinhronizacije.
- **Inicijalizacija i popunjavanje Obsidian memorije (`wiki/`):**
  - `wiki/architecture/overview.md`: Šestoslojni arhitektonski model i tokovi podataka.
  - `wiki/decisions/ADR-0001-portable-usb-architecture.md`: Go binarni CLI vs desktop, nula zavisnosti, headless OAuth.
  - `wiki/decisions/ADR-0002-hardware-write-protect-and-device-fingerprint.md`: HW Write-Protect detekcija, %TEMP% sandbox, očitavanje serijskih brojeva i izolacija radnih prostora (`devices/<DeviceTag>/`).
  - `wiki/decisions/ADR-0003-servis-hub-bidirectional-sync.md`: Specifikacija dvosmerne sinhronizacije sesija, UDP Auto-Discovery i offline reda čekanja.
  - `wiki/domain/glossary.md`: Kompletiran rečnik domena sa preko 20 stručnih pojmova.
  - `wiki/memory/gotchas.md`: Dokumentovane zamke (conhost bafer neslaganje, cmd crash pri chcp 65001, generički serijski brojevi, HW write-protect ograničenja).
  - `wiki/index.md`: Ažuriran MOC indeks sa unakrsnim vezama ka svoj dokumentaciji.

### [2026-10-10 17:30] - Implementacija ADR-0004: Pre-Flight Auto-Registracija, Kontekstni Izvodi i In-Flight Checkpoint Sinhronizacija
- **Servis Hub Server proširenja (`servishub/`):**
  - Implementirana nova ruta `POST /api/devices/{tag}/register` za trenutno otvaranje digitalnog kartona novog računara pre startovanja AGY sesije (`DEVICE_INFO.json`, inicijalni `SERVISNI_DNEVNIK.md`, status `U_DIJAGNOSTICI`).
  - Implementirana nova ruta `POST /api/devices/{tag}/checkpoint` za perzistenciju međurezultata tokom dijagnostike i dinamičko ažuriranje statusa flote u `FleetStore` (`Kvar (AGY)`, `Servisiran (AGY)`, `Čeka delove (AGY)`).
- **AGY Serviser Klijent unapređenja (`scripts/` i `Start-ServisAI.ps1`):**
  - `Sync-ServiceHub.ps1`:
    - Dodato generisanje `devices/<DeviceTag>/SERVIS_HUB_HISTORY.md` iz preuzete istorije, omogućavajući AI asistentu trenutan uvid u prethodne radove kolega i recidivne kvarove.
    - Implementiran inteligentni Merge (spajanje) dnevnika sa Hub-a u lokalni `SERVISNI_DNEVNIK.md` bez brisanja i dupliranja.
    - Implementirana pretraga sa rezervnim fallback-om po serijskom broju (`/api/devices/by-serial/{serial}/history`).
    - Dodate funkcije `Invoke-HubRegister` (`-Register`) i `Invoke-HubCheckpoint` (`-Checkpoint`).
    - Proširen `Invoke-HubFlushPending` za procesiranje zaostalih paketa tipa `_REGISTER_` i `_CHECKPOINT_`.
  - `scripts/Save-ServiceProgress.ps1`:
    - Kreirana namenska skripta koju AI asistent poziva čim otkrije kvar ili završi ključnu fazu dijagnostike.
  - `Start-ServisAI.ps1`:
    - U pre-flight fazi automatski poziva registraciju na Hub-u ako uređaj prethodno nije evidentiran.
  - `AGENTS.md`:
    - Ažurirana pravila za obavezno čitanje `SERVIS_HUB_HISTORY.md` i okidanje checkpointa preko `Save-ServiceProgress.ps1`.
- **QA Verifikacija i E2E Testovi:**
  - `tests/test_e2e_sync.py`: Proširen sa 6 na 11 sveobuhvatnih integracionih scenarija (11/11 PASSED).
  - `Servis Hub` test suite: 214/214 PASSED.
- **Arhitektonska Baza Znanja (Wiki):**
  - Kreiran `wiki/decisions/ADR-0004-preflight-registration-and-live-checkpoint.md`.
  - Ažuriran `wiki/index.md` i `README.md`.

