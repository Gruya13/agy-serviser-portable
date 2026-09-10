# Uputstvo za Binarni Fajl Antigravity CLI (`bin\agy.exe`)

Ovaj folder (`bin\`) je predviđen za zvanični izvršni fajl Antigravity CLI za Windows:
- **Putanja:** `bin\agy.exe`

## Kako obezbediti `agy.exe` za Windows:

1. **Zvanično preuzimanje / Instalacija:**
   - Ukoliko imate instaliran Antigravity CLI na Windows radnoj stanici, `agy.exe` se podrazumevano nalazi u vašem korisničkom folderu:
     `%USERPROFILE%\.local\bin\agy.exe` ili `%LOCALAPPDATA%\Programs\Antigravity\agy.exe`
   - Prekopirajte `agy.exe` u ovaj folder (`bin\agy.exe` na USB memoriji).

2. **Provera verzije:**
   - Otvorite komandnu liniju u ovom folderu i proverite verziju:
     ```cmd
     agy.exe --help
     ```

3. **Napomena o Git repozitorijumu:**
   - Binarni fajlovi (`*.exe`) su automatski ignorisani kroz `.gitignore` kako ne bi opterećivali Git repozitorijum.
   - Priprema USB memorije podrazumeva ručno kopiranje najnovijeg `agy.exe` u ovaj direktorijum.
