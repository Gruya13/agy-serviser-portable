# Antigravity CLI Portable - Prenosivi Servisni AI Asistent

Prenosivi (portable) USB alat namenjen računarskim serviserima za brzu, tačnu i bezbednu hardversku i softversku dijagnostiku na operativnim sistemima Windows 10 i Windows 11.

Sistem pokreće zvanični **Antigravity CLI (`agy`)** povezan sa vašom **Google AI Pro** pretplatom, omogućavajući rad sa vrhunskim Gemini modelima bez plaćanja dodatnih API troškova i bez ugrožavanja vaših ličnih lozinki na klijentskim mašinama.

---

## Ključne mogućnosti

- **Zero-Trust autorizacija preko telefona:** Klijentski računar nikada ne vidi vašu Google lozinku. Autorizacija se vrši skeniranjem linka/koda na vašem telefonu.
- **Trajna prijava na otključanom USB-u:** Jednom se prijavite u svojoj radionici, a na svim klijentskim mašinama radite odmah bez ponovnog korišćenja telefona.
- **Automatska USB samoodbrana i samočišćenje:** Pre i posle svake sesije, sistem skenira USB na viruse, uklanja maliciozne prečice (`.lnk`), sumnjive skripte i vakciniše `autorun.inf`.
- **Hardware Write-Protect podrška:** Ako se koristi zaključani fleš, profil se smešta u `%TEMP%` klijenta i automatski samouništava pri zatvaranju.
- **Root-Cause analiza:** AI agent fokusiran na pronalaženje tačnog uzroka kvara umesto generičkih saveta.
- **Strogo Non-Destructive pravilo:** Agent nikada ne vrši izmene na sistemu klijenta bez vaše eksplicitne potvrde.
- **Ugrađene servisne veštine (Skills):**
  - `/smart-health` - Provera zdravlja i istrošenosti NVMe/SSD/HDD diskova.
  - `/event-log-triage` - Filtriranje kritičnih grešaka i neočekivanih gašenja (Kernel-Power, WHEA).
  - `/bsod-analyzer` - Analiza uzroka rušenja sistema i Minidump datoteka.
  - `/system-integrity` - Bezbedna kontrola integriteta sistema (SFC / DISM).
  - `/malware-triage` - Detekcija sumnjivih autorun unosa, skripti i procesa.
  - `/usb-defense` - Skeniranje i automatsko čišćenje USB medijuma od malvera.

---

## Struktura USB diska

```text
USB:\ServisAI\
├── Start-ServisAI.bat            # Brzi dvoklik launcher (trazi UAC i pokrece PowerShell)
├── Start-ServisAI.ps1            # Glavna orkestracija, mrezna provera i ciscenje
├── AGENTS.md                     # Sistemska pravila za ponasanje agenta u servisu
├── .gitignore                    # Zastita privatnih podataka i tokena
├── config\
│   └── settings.json             # Podesavanja CLI-ja i modela
├── bin\
│   ├── agy.exe                   # Antigravity CLI izvrsni fajl za Windows x64
│   └── README_BIN.md             # Uputstvo za preuzimanje i postavljanje agy.exe
├── scripts\                      # Samostalne PowerShell dijagnosticke skripte
│   ├── Get-DiskHealth.ps1
│   ├── Get-EventLogTriage.ps1
│   ├── Get-MinidumpReport.ps1
│   ├── Test-SystemIntegrity.ps1
│   └── Find-SuspiciousAutoruns.ps1
├── .agents\
│   └── skills\                   # Specijalizovane servisne vestine za AI agenta
│       ├── smart-health\
│       ├── event-log-triage\
│       ├── bsod-analyzer\
│       ├── system-integrity\
│       └── malware-triage\
├── second_brain\
│   └── AI_Agent_Guidelines.md    # Standardi i pravila projekta
└── istorija_izrade.md            # Dnevnik izmena i implementacija
```

---

## Uputstvo za pripremu i korišćenje

### 1. Priprema USB fleša (jednokratno)
1. Prekopirajte sadržaj ovog projekta na USB memoriju u željeni folder (npr. `E:\ServisAI`).
2. Preuzmite zvanični `agy.exe` za Windows i smestite ga u folder `bin\agy.exe` (pogledajte `bin\README_BIN.md`).

### 2. Korišćenje na klijentskom računaru
1. Ubacite USB memoriju u računar klijenta (Windows 10 ili 11).
2. Pokrenite **`Start-ServisAI.bat`** (skripta će automatski zatražiti Administratorska prava).
3. **Povezivanje preko telefona:**
   - U terminalu će se ispisati Google OAuth link.
   - Otvorite taj link na svom pametnom telefonu gde ste prijavljeni na svoj Google AI Pro nalog.
   - Potvrdite pristup i prepišite kratki verifikacioni kod u terminal na računaru klijenta.
4. **Rad sa asistentom:**
   - Možete slobodno pitati asistenta na srpskom jeziku (npr. *"Proveri diskove i vidi zasto se racunar gasio"*).
   - Asistent će ponuditi izvršenje skripte ili komande, a vi tasterom `y` odobravate izvršenje.
5. **Završetak rada:**
   - Upišite `/exit` ili pritisnite `Ctrl+D`.
   - Skripta automatski odjavljuje vaš nalog (`/logout`) i briše sve privremene tokene i keš. Klijentski računar ostaje 100% čist.
