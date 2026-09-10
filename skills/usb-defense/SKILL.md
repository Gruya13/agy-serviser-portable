---
name: usb-defense
description: Samoodbrana, skeniranje i automatsko samočišćenje USB medijuma od virusa, crva, prečica (.lnk) i neautorizovanih modifikacija.
---

# Veština: Samoodbrana i Samočišćenje USB-a (usb-defense)

Ova veština omogućava AI agentu da proveri integritet sopstvenog USB medijuma, detektuje da li je zaraženi klijentski računar pokušao da inficira USB, i automatski ukloni maliciozne datoteke.

## Kada koristiti ovu veštinu:
- Serviser zatraži proveru USB fleša na viruse ("očisti usb", "proveri fleš", "da li je fleš zaražen").
- Završena je analiza jako zaraženog računara, pa je preporučljivo očistiti fleš pre vađenja.
- Primetne su neočekivane `.lnk` prečice ili skriveni fajlovi na USB-u.

## Koraci izvršavanja:

1. **Pokretanje skripte za zaštitu i samočišćenje:**
   Izvrši PowerShell skriptu sa automatskim uklanjanjem pretnji i vakcinacijom:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File ".\scripts\Protect-USBIntegrity.ps1" -AutoClean -Vaccinate
   ```

2. **Šta skripta proverava i čisti:**
   - **USB Shortcut crvi:** Uklanja sve maliciozne `.lnk`, `.vbs`, `.js`, `.scr` fajlove koje virusi automatski kreiraju na eksternim diskovima.
   - **Zalutali izvršni fajlovi:** Uklanja nepoznate `.exe` fajlove u korenu USB-a.
   - **Vakcinacija autorun.inf:** Osigurava da je `autorun.inf` zaštićen folder sa sistemskim i skrivenim atributima kako malver ne bi mogao da ga prepiše.
   - **Integritet heševa (Tamper Detection):** Proverava da li je kôd u `scripts\` ili `bin\agy.exe` ostao originalan.

3. **Format izveštaja serviseru:**
   - **Status USB-a:** [Čist / Očišćeno N pretnji / Upozorenje o modifikaciji].
   - **Preduzete akcije:** Izveštaj o uklonjenim datotekama.
   - **Preporuka:** Potvrda da je USB bezbedan za povezivanje na sledeću mašinu.
