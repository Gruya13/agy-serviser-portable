---
name: smart-health
description: Analiza zdravstvenog stanja i SMART parametara diskova (NVMe, SSD, HDD), otkrivanje neispravnih sektora, procene radnog veka i temperature.
---

# Veština: Analiza Zdravlja Diskova (smart-health)

Ova veština omogućava preciznu hardversku dijagnostiku stanja skladišnih medijuma na klijentskom računaru.

## Kada koristiti ovu veštinu:
- Korisnik prijavljuje usporen rad računara, "zamrzavanje" ili škljocanje.
- Sumnja se na otkaz diska, degradaciju NVMe fleš memorije ili loše sektore.
- Serviser unese upit "proveri diskove", "smart provera", "stanje SSD-a" ili slično.

## Koraci izvršavanja:

1. **Pokretanje dijagnostičke skripte:**
   Izvrši pripremljenu PowerShell skriptu u terminalu:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File ".\scripts\Get-DiskHealth.ps1"
   ```

2. **Interpretacija rezultata za servisera:**
   - **Tip medijuma i interfejs:** Razlikuj NVMe od SATA SSD i magnetnih HDD diskova.
   - **Istrošenost (Wear Level):** Kod NVMe/SSD, ako je istrošenost veća od 80%, upozori servisera na rizik od prebacivanja u Read-Only režim.
   - **Greške u čitanju/pisanju:**
     - Bilo koji broj `ReadErrorsUncorrected` ili `WriteErrorsUncorrected` ukazuje na hardversku neispravnost fleš NAND memorije ili magnetnih ploča.
     - Disk sa neispravljivim greškama odmah proglasi **kritičnim** za zamenu i preporuči hitan bekap podataka.
   - **Temperatura:** Normalne radne temperature su do 55°C za NVMe i do 45°C za HDD/SATA. Sve preko 65°C predstavlja termalni rizik.

3. **Format izveštaja serviseru:**
   - **Status diskova:** [Zdrav / Upozorenje / Kritično za zamenu]
   - **Ključni parametri:** Istrošenost, greške, preostali prostor.
   - **Servisna preporuka:** (npr. "Disk je potpuno ispravan" ili "Hitno klonirati podatke, disk ima neispravljive sektore").
