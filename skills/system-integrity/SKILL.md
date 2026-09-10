---
name: system-integrity
description: Provera integriteta Windows komponentnog skladišta (DISM) i sistemskih datoteka (SFC), analiza CBS logova i bezbedna priprema za popravku.
---

# Veština: Provera Integriteta Sistema (system-integrity)

Ova veština omogućava kontrolu i popravku oštećenih Windows sistemskih komponenti bez ugrožavanja korisničkih podataka i postavki.

## Kada koristiti ovu veštinu:
- Windows prijavljuje greške pri instalaciji ažuriranja (Windows Update fails).
- Sistemske komponente (Start meni, Settings, Explorer) se ruše ili ne reaguju.
- Nakon uklanjanja virusa radi vraćanja originalnih sistemskih biblioteka.

## Koraci izvršavanja:

1. **Pokretanje bezbedne dijagnostike (Non-Destructive):**
   Izvrši početnu proveru bez promena:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File ".\scripts\Test-SystemIntegrity.ps1"
   ```

2. **Tumačenje rezultata:**
   - **SFC status:**
     - Ako je status "Windows Resource Protection did not find any integrity violations": Fajl sistem i DLL biblioteke su netaknuti.
     - Ako je status "found integrity violations and successfully repaired them": Oštećenja su postojala ali su uspešno zakrpljena iz lokalnog keša.
     - Ako je status "found integrity violations but was unable to fix some of them": Lokalni keš (`WinSxS`) je oštećen. Neophodan je DISM RestoreHealth.
   - **DISM status:**
     - `CheckHealth`: Brzo očitava flag korupcije.
     - Ako je skladište "repairable", predloži serviseru pokretanje popravke sa internet izvora.

3. **Preporučene komande za popravku (zahtevaj potvrdu servisera pre pokretanja):**
   Ukoliko su otkrivena oštećenja, ponudi serviseru tačne komande za popravku:
   ```cmd
   DISM.exe /Online /Cleanup-image /RestoreHealth
   sfc /scannow
   ```
