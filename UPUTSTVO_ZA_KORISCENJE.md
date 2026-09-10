# Kompletan Priručnik za Rad sa Prenosivim Servisnim AI Asistentom

Dobrodošli u zvanično uputstvo za korišćenje **Antigravity CLI Portable Servisnog Asistenta**. Ovaj alat je namensko rešenje za računarske servise, dizajnirano da omogući brzu, tačnu i bezbednu dijagnostiku hardvera i operativnog sistema na klijentskim računarima (Windows 10 i Windows 11).

Sistem koristi zvanični terminalski agent **Antigravity CLI (`agy`)** povezan sa vašom **Google AI Pro** pretplatom, što obezbeđuje rad sa vodećim Gemini modelima bez dodatnih troškova po tokenu i bez rizika od kompromitovanja vaših ličnih lozinki.

---

## Sadržaj

1. [Arhitektura i struktura direktorijuma](#1-arhitektura-i-struktura-direktorijuma)
2. [Priprema USB fleša (Jednokratni postupak)](#2-priprema-usb-fleša-jednokratni-postupak)
3. [Jednokratna prijava (Trajna sesija na flešu)](#3-jednokratna-prijava-trajna-sesija-na-flešu)
4. [Procedura rada na klijentskom računaru](#4-procedura-rada-na-klijentskom-računaru)
5. [Katalog servisnih veština (Skills) i primeri upita](#5-katalog-servisnih-veština-skills-i-primeri-upita)
6. [Bezbednosni mehanizmi i samoodbrana USB-a](#6-bezbednosni-mehanizmi-i-samoodbrana-usb-a)
7. [Režimi rada: Otključan vs Write-Protected fleš](#7-režimi-rada-otključan-vs-write-protected-fleš)
8. [Česta pitanja i rešavanje problema (Troubleshooting)](#8-česta-pitanja-i-rešavanje-problema-troubleshooting)

---

## 1. Arhitektura i struktura direktorijuma

Na USB memoriji se nalazi sledeća organizacija datoteka:

```text
USB:\ServisAI\
│
├── Start-ServisAI.bat            # Brzi dvoklik pokretač (automatska UAC elevacija)
├── Start-ServisAI.ps1            # Glavni orkestrator (mrežna provera, profil, zaštita)
├── AGENTS.md                     # Glavna sistemska pravila za ponašanje AI agenta
├── README.md                     # Osnovni pregled projekta
├── UPUTSTVO_ZA_KORISCENJE.md     # Ovaj detaljni priručnik
├── .gitignore                    # Zaštita od curenja sesija i privatnih tokena
│
├── bin\                          # Izvršni fajlovi alata
│   ├── agy.exe                   # Zvanični Antigravity CLI za Windows x64
│   └── README_BIN.md             # Uputstvo za postavljanje binarnog fajla
│
├── config\                       # Konfiguracija radnog okruženja
│   └── settings.json             # Postavke modela (gemini-2.5-pro) i pravila rada
│
├── scripts\                      # Nativne PowerShell servisne dijagnostičke skripte
│   ├── Get-DeviceInfo.ps1        # Identifikacija serijskog broja i hardverske karte
│   ├── Get-DiskHealth.ps1        # SMART i NVMe provera, radni vek i greške
│   ├── Get-EventLogTriage.ps1    # Analiza kriticnih padova (Kernel-Power, WHEA)
│   ├── Get-MinidumpReport.ps1    # Analiza BSOD rušenja i oštećenih drajvera
│   ├── Test-SystemIntegrity.ps1  # Provera integriteta sistema (SFC / DISM)
│   ├── Find-SuspiciousAutoruns.ps1 # Detekcija sumnjivih procesa i autorun unosa
│   └── Protect-USBIntegrity.ps1  # Samoodbrana, imunizacija i čišćenje USB-a
│
├── .agents\skills\               # Servisne veštine koje agent autonomno koristi
│   ├── device-audit\SKILL.md     # Veština za hardversku kartu i serijski broj
│   ├── smart-health\SKILL.md     # Veština za dijagnostiku diskova
│   ├── event-log-triage\SKILL.md # Veština za trijažu logova
│   ├── bsod-analyzer\SKILL.md    # Veština za plave ekrane
│   ├── system-integrity\SKILL.md # Veština za integritet Windows-a
│   ├── malware-triage\SKILL.md   # Veština za analizu malvera
│   └── usb-defense\SKILL.md      # Veština za samoodbranu i samočišćenje fleša
│
├── devices\                      # Automatski kreirani servisni kartoni i odvojeni cetovi po masinama
│   └── <DeviceTag>\              # npr. LENOVO_ThinkPad-T14_PF2A1234
│       ├── DEVICE_INFO.md        # Hardverska specifikacija (CPU, RAM, GPU, diskovi, serijski broj)
│       ├── SERVISNI_DNEVNIK.md   # Hronologija poseta i intervencija za ovaj racunar
│       ├── reports\              # Dijagnosticki izvestaji vezani iskljucivo za ovu masinu
│       └── sessions\             # Istorija cetova i konverzacija za ovaj racunar
│
├── data\                         # Korisnički profil i trajno sačuvana prijava sesije
│   └── .gemini\                  # Izolovani tokeni (deljeni za sve masine, nema ponovnog logovanja)
│
└── second_brain\                 # Inženjerska dokumentacija projekta
    └── AI_Agent_Guidelines.md    # Standardi rada, bezbednosti i koda
```

---

## 2. Priprema USB fleša (Jednokratni postupak)

### Korak 1: Priprema medijuma
- Preporučuje se USB fleš memorija (USB 3.0/3.1) formatirana kao **NTFS** ili **exFAT**.
- Iskopirajte ceo sadržaj ovog projekta u željeni folder na USB-u (npr. `E:\ServisAI` ili u koren diska).

### Korak 2: Preuzimanje zvaničnog `agy.exe` za Windows
Binarni fajl `agy.exe` se ne čuva u Git-u radi optimizacije veličine repozitorijuma. Potrebno ga je preuzeti jednom:
1. Na vašem Windows radnom računaru otvorite **PowerShell** i unesite:
   ```powershell
   irm https://antigravity.google/cli/install.ps1 | iex
   ```
2. Skripta će preuzeti zvanični `agy.exe` u vaš korisnički profil:
   `C:\Users\<VašeKorisničkoIme>\AppData\Local\agy\bin\agy.exe`
3. Prekopirajte taj `agy.exe` fajl na vaš fleš disk u:
   `USB:\ServisAI\bin\agy.exe`

---

## 3. Jednokratna prijava (Trajna sesija na flešu)

Da ne biste na svakom klijentskom računaru vadili telefon i unosili kodove, sistem omogućava **trajno pamćenje prijave na flešu**:

1. Ubacite pripremljeni USB u **svoj radni računar** u servisu.
2. Pokrenite **`Start-ServisAI.bat`**.
3. U terminalu će se ispisati Google OAuth autorizacioni link:
   ```text
   Please visit this URL on any device to authenticate:
   https://accounts.google.com/o/oauth2/auth?client_id=...
   Enter authorization code: 
   ```
4. **Na svom pametnom telefonu** (ili browseru gde ste ulogovani na svoj Google nalog sa **Google AI Pro** pretplatom):
   - Otvorite link i kliknite **Allow / Dozvoli**.
   - Dobićete kratak verifikacioni kod (npr. `4/0AY0e...`).
5. Prepišite kod u konzolu i pritisnite **Enter**.
6. Kada se asistent pokrene, ukucajte `/exit` da zatvorite sesiju.

> [!IMPORTANT]
> Vaša prijava je sada trajno sačuvana u folderu `USB:\ServisAI\data\`. Na svim budućim klijentskim mašinama asistent će se startovati **odmah, bez potrebe za ponovnim logovanjem ili korišćenjem telefona**!

---

## 4. Procedura rada na klijentskom računaru

Kada klijent donese računar na servis (Windows 10 ili 11):

1. **Ubacite USB fleš** u računar klijenta.
2. Pokrenite **`Start-ServisAI.bat`** dvoklikom.
3. Windows će prikazati UAC dijalog za povišenje prava – kliknite **Yes** (Administratorska prava su neophodna za čitanje hardverskih registara, Minidump fajlova i Event Log-a).
4. Skripta automatski u sekundi izvršava:
   - Proveru internet veze ka Google servisima.
   - USB imunizaciju i proveru da li na flešu ima virusa sa klijentske mašine.
   - Preusmeravanje profila na `data\` folder na USB-u (računar klijenta ostaje netaknut).
   - Pokretanje Antigravity CLI asistenta.
5. Asistent vas dočekuje sa servisnim promptom spremnim za rad.

---

## 5. Katalog servisnih veština (Skills) i primeri upita

Komunicirajte sa asistentom na čistom **srpskom jeziku**, opušteno ili profesionalno. Asistent automatski prepoznaje nameru i poziva odgovarajuće dijagnostičke skripte:

---

### Veština 1: Provera zdravlja diskova (`/smart-health`)
- **Kada se koristi:** Računar "koči", sporo otvara programe, zaleže u radu ili sumnjate na dotrajao SSD/HDD.
- **Primer upita:**
  - *"Proveri diskove na računaru i reci mi u kakvom su stanju."*
  - *"Kakvo je stanje NVMe drajva i koliko je istrošen?"*
- **Šta asistent radi:**
  - Pokreće `.\scripts\Get-DiskHealth.ps1`.
  - Očitava Wear Level (procenat istrošenosti NAND memorije), radne sate, neispravljive greške u čitanju/pisanju, temperature i slobodan prostor po particijama.
  - Daje jasnu preporuku: npr. *"Disk je zdrav"* ili *"Kritično: Disk ima neispravljive greške, odmah klonirajte podatke!"*

---

### Veština 2: Analiza gašenja i pada sistema (`/event-log-triage`)
- **Kada se koristi:** Računar se iznenada gasi u igrama ili radu, restartuje se ili zamrzava.
- **Primer upita:**
  - *"Vidi zašto se mašina gasila u poslednja 24 sata."*
  - *"Pregledaj Event Log i proveri Kernel-Power greške."*
- **Šta asistent radi:**
  - Pokreće `.\scripts\Get-EventLogTriage.ps1 -Hours 24`.
  - Analizira Kernel-Power (Event ID 41) i istražuje događaje neposredno pre gašenja.
  - Otkriva da li je uzrok Disk timeout, WHEA hardverska greška procesora/ploče ili nestanak napona (neispravno napajanje).

---

### Veština 3: Analiza plavih ekrana smrti (`/bsod-analyzer`)
- **Kada se koristi:** Računar izbacuje plavi ekran (BSOD).
- **Primer upita:**
  - *"Ima li minidump fajlova i zašto je pao plavi ekran?"*
  - *"Objasni mi uzrok poslednjeg BSOD-a."*
- **Šta asistent radi:**
  - Pokreće `.\scripts\Get-MinidumpReport.ps1`.
  - Vadi Stop kôd (npr. `0x133 DPC_WATCHDOG_VIOLATION`, `0x124 WHEA_UNCORRECTABLE_ERROR`, `0x7E`).
  - Identifikuje tačan drajver (`.sys`) koji je izazvao krah i predlaže servisno rešenje (zamena drajvera, testiranje memorije).

---

### Veština 4: Kontrola integriteta sistema (`/system-integrity`)
- **Kada se koristi:** Windows prijavljuje greške, Windows Update ne prolazi, Explorer se ruši.
- **Primer upita:**
  - *"Proveri integritet sistema i komponentno skladište."*
  - *"Testiraj sistemske datoteke preko SFC i DISM."*
- **Šta asistent radi:**
  - Pokreće bezbednu (non-destructive) proveru `DISM /CheckHealth` i `SFC /verifyonly`.
  - Javlja da li je sistem zdrav ili oštećen, i tek uz vaše odobrenje nudi pokretanje popravke (`/RestoreHealth` i `sfc /scannow`).

---

### Veština 5: Trijaža sumnjivih procesa i malvera (`/malware-triage`)
- **Kada se koristi:** Iskaču prozori, sumnja na viruse, spori servisi ili neželjeni programi.
- **Primer upita:**
  - *"Proveri autorun unose i ima li sumnjivih procesa u Temp folderu."*
  - *"Pregledaj zakazane zadatke na viruse."*
- **Šta asistent radi:**
  - Pokreće `.\scripts\Find-SuspiciousAutoruns.ps1`.
  - Analizira Registry Run lokacije, Task Scheduler i aktivne procese koji se pokreću iz korisničkih privremenih foldera.

---

### Veština 6: Samoodbrana i samočišćenje USB-a (`/usb-defense`)
- **Kada se koristi:** Pre nego što izvadite fleš iz visoko rizičnog ili zaraženog računara.
- **Primer upita:**
  - *"Očisti fleš od virusa."*
  - *"Proveri da li je klijent pokušao da zarazi USB."*
- **Šta asistent radi:**
  - Pokreće `.\scripts\Protect-USBIntegrity.ps1 -AutoClean -Vaccinate`.
  - Uništava sve prečice (`.lnk`), `.vbs` skripte i neovlašćene `.exe` fajlove, i potvrđuje da je fleš čist.

---

## 6. Bezbednosni mehanizmi i samoodbrana USB-a

Rad u servisu nosi stalan rizik od kontaminacije fleš memorije. Ovaj sistem poseduje višeslojnu automatsku zaštitu:

1. **Pre-Session & Post-Session Auto-Clean:**
   Svaki put kada pokrenete i svaki put kada ugasite `Start-ServisAI.bat`, skripta automatski skenira celokupnu USB fleš memoriju i uništava sve poznate oblike USB crva i prečica.
2. **USB Imunizacija (Vakcina):**
   U korenu fleša se nalazi zaštićen `autorun.inf` folder sa zaključanim sistemskim i skrivenim atributima, što sprečava zlonamerni softver da manipuliše automatskim pokretanjem.
3. **Kontrola integriteta (Tamper Detection):**
   Svi ključni fajlovi (`scripts\*.ps1`, `Start-ServisAI.bat`, `AGENTS.md`) štite se kontrolnim SHA-256 heševima. Ako virus pokuša da izmeni neku skriptu, sistem vas odmah upozorava.
4. **Strogi Non-Destructive princip:**
   AI agent **nikada** neće samostalno obrisati korisničke podatke, menjati Registry bazu ili formatirati particiju. Pre svake izmene, agent detaljno objašnjava šta komanda radi i čeka da vi pritisnete `y` (odobri) ili `n` (odbij).

---

## 7. Režimi rada: Otključan vs Write-Protected fleš

Sistem automatski prilagođava rad zavisno od hardvera vašeg fleša:

| Funkcionalnost | Otključan USB (Standardni fleš) | Zaključan USB (Hardware Write-Protect) |
| :--- | :--- | :--- |
| **Gde se čuvaju podaci sesije** | `USB:\ServisAI\data\` | `%TEMP%\ServisAI_...` (RAM/Privremeni disk) |
| **Trajanje Google prijave** | **Trajno sačuvano** (ulogujete se jednom) | **Jednokratno** (odjava po zatvaranju prozora) |
| **Tragovi na klijentskom PC-ju** | **Nula** (sve ide na USB) | **Nula** (temp folder se potpuno briše pri izlasku) |
| **Zaštita od virusa** | Automatsko samočišćenje pre i posle sesije | Fizička nemogućnost upisa na nivou čipa |
| **Preporučena primena** | 95% svakodnevnih servisnih intervencija | Ekstremno zaraženi računari (Ransomware/Crv) |

---

## 8. Česta pitanja i rešavanje problema (Troubleshooting)

### Šta ako računar klijenta nema internet?
- Antigravity CLI komunicira sa velikim Google AI Pro modelom u oblaku, pa je internet veza neophodna za rad samog asistenta.
- **Rešenje:** Povežite klijentski računar na servisni Wi-Fi ili LAN pre pokretanja. Sve pomoćne PowerShell skripte u folderu `scripts\` možete pokretati i samostalno u običnom PowerShell-u čak i bez interneta.

### Šta ako se pojavi greška da nedostaje `bin\agy.exe`?
- To znači da niste prekopirali izvršni fajl na USB memoriju.
- **Rešenje:** Pogledajte [Poglavlje 2](#2-priprema-usb-fleša-jednokratni-postupak) ovog uputstva i preuzmite `agy.exe` prateći korake.

### Kako da promenim ili odjavim svoj Google nalog sa fleša?
- Ako želite da prodate fleš, pozajmite ga kolegi ili promenite Google nalog:
  - U toku rada asistenta ukucajte `/logout`.
  - Ili pokrenite orkestrator sa parametrom za odjavu:
    ```powershell
    powershell.exe -ExecutionPolicy Bypass -File ".\Start-ServisAI.ps1" -Logout
    ```
  - Ovo trenutno briše sačuvani token iz foldera `data\`.

### Kako se pravilno završava rad sa asistentom?
- U konzoli jednostavno ukucajte:
  ```text
  /exit
  ```
  *(ili pritisnite `Ctrl+D` ili kliknite na `X` na prozoru)*.
- Skripta će automatski izvršiti završno samočišćenje USB-a i prijaviti da je sesija bezbedno okončana.
