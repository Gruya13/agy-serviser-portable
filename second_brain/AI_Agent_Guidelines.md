# Smernice za AI Agente (AI Agent Guidelines) - Antigravity CLI Portable

Ovaj dokument definiše standarde ponašanja, bezbednosne protokole i inženjerska pravila za sve AI agente koji učestvuju u razvoju i održavanju projekta **Antigravity CLI Portable (Prenosivi Servisni Asistent)**.

---

## 1. Osnovna načela projekta

1. **Jezik komunikacije i razmišljanja:**
   - Celokupna komunikacija sa korisnikom i interno razmišljanje agenta odvijaju se isključivo na **srpskom jeziku**.
2. **Bezbednost klijentskih računara (Non-Destructive First):**
   - Alat se pokreće na operativnim i servisiranim računarima klijenata sa punim administratorskim privilegijama.
   - **Stroga zabrana destruktivnih akcija:** Bilo kakvo brisanje sistemskih datoteka, formatiranje particija, nasilno menjanje Registry baze ili brisanje servisa **nikada** se ne sme izvršiti automatski. Agent mora predložiti dijagnostičku komandu i zatražiti eksplicitnu potvrdu servisera pre izvršenja izmene.
   - Sve skripte moraju imati ugrađeno rukovanje greškama (`try/catch`, `-ErrorAction SilentlyContinue`) kako ne bi prekinule rad niti oštetile sistem.
3. **Zaštita privatnosti i nulto poverenje (Zero-Trust):**
   - Lični podaci i Google nalog servisera nikada se ne unose direktno u veb pregledač klijenta. Koristi se isključivo headless/remote autorizacija putem telefona.
   - Po završetku sesije, skripte moraju osigurati odjavu naloga i potpuno uklanjanje privremenih tokena sa klijentskog diska.
4. **Očuvanje integriteta medijuma (Read-Only Awareness):**
   - Skripte moraju podržavati rad sa fleš memorijama koje imaju hardversku zaštitu od upisa (Write-Protect prekidač).
   - Ako je fleš zaključan, privremeni podaci sesije preusmeravaju se u `%TEMP%` klijentske mašine i brišu pri gašenju.

---

## 2. Inženjerski i skripting standardi

1. **PowerShell standardi:**
   - Primarna kompatibilnost sa **Windows PowerShell 5.1** (podrazumevano instaliran na Windows 10 i 11), uz podršku za novije PowerShell 7+ verzije.
   - Korišćenje nativnih CIM/WMI i Storage modula (`Get-CimInstance`, `Get-PhysicalDisk`, `Get-StorageReliabilityCounter`, `Get-WinEvent`).
   - Sve skripte moraju podržavati parametrizaciju i vraćati strukturirane objekte ili čitljiv format za prosleđivanje AI modelu.
2. **Batch standardi (`.bat`):**
   - Skripta `Start-ServisAI.bat` mora garantovati proveru administratorskih prava (`net session`) i samostalno pokrenuti UAC elevaciju (`-Verb RunAs`) ukoliko proces nije pokrenut sa povišenim privilegijama.
   - Korišćenje relativnih putanja (`%~dp0`) radi nezavisnosti od dodeljenog slova USB drajva.
3. **Kvalitet koda i evidencija izmena:**
   - Nakon svake implementacije ili ispravke, obavezno je uneti sažetak urađenog u `istorija_izrade.md` sa tačnim datumom i vremenom.
   - Pre svakog commit-a proveriti ispravnost skripti i alata.
