---
title: "Pregled Arhitekture Projekta: AGY Serviser Portable"
type: architecture
created: 2026-10-09
updated: 2026-10-09
tags:
  - architecture
  - overview
  - agy-serviser
  - portable-usb
---

# Pregled Arhitekture Projekta: AGY Serviser Portable

Ovaj dokument definiše sveobuhvatnu arhitekturu, podsisteme, bezbednosni model i tokove podataka projekta **AGY Serviser Portable** (Antigravity CLI Portable).

---

## 🎯 1. Cilj i Svrha
**AGY Serviser Portable** je prenosivi (portable) USB dijagnostički alat namenjen računarskim serviserima za brzu, tačnu i bezbednu hardversku i softversku analizu operativnih sistema **Windows 10 i Windows 11**.

### Ključni inženjerski postulati:
1. **Nulta instalacija (Zero-Dependency):** Alat ne zahteva instalaciju pozadinskih okruženja (Python, Node.js) na klijentskoj mašini. Izvršno jezgro je samostalni Go binarni fajl `bin/agy.exe` sa nativnim PowerShell skriptama.
2. **Zero-Trust autorizacija:** Nalog i lozinka servisera nikada se ne unose u pregledač klijenta; koristi se Headless Remote OAuth preko telefona.
3. **Root-Cause analiza:** Fokus na utvrđivanje primarnog uzroka kvara umesto površnih reinstalacija.
4. **Centralna integracija sa radionicom (ADR-0003):** Dvosmerna telemetrijska sinhronizacija sa serverom **Servis Hub** uz podršku za rad bez mreže (offline queue).

---

## 🏗️ 2. Šestoslojni Arhitektonski Model

```mermaid
flowchart TD
    subgraph L1 ["1. Pokretački Sloj (Bootstrap)"]
        BAT["Start-ServisAI.bat"]
        PS1["Start-ServisAI.ps1"]
    end

    subgraph L2 ["2. Bezbednosni Sloj (Security & Sandbox)"]
        PROT["scripts/Protect-USBIntegrity.ps1"]
        WP["HW Write-Protect Detekcija"]
        SANDBOX["%TEMP% Sandbox (po potrebi)"]
    end

    subgraph L3 ["3. Identifikacioni Sloj (Fingerprinting)"]
        DEV["scripts/Get-DeviceInfo.ps1"]
        DEVICES["devices/<DeviceTag>/"]
    end

    subgraph L4 ["4. Integracioni Sloj (Servis Hub Sync)"]
        SYNC["scripts/Sync-ServiceHub.ps1"]
        UDP["UDP Auto-Discovery (:8888)"]
        QUEUE["pending_sync/ (Offline Red)"]
    end

    subgraph L5 ["5. Agentsko Jezgro (AI Core)"]
        CLI["bin/agy.exe"]
        PROMPT["AGENTS.md"]
        SKILLS[".agents/skills/ (7 Servisnih Veština)"]
    end

    subgraph L6 ["6. Post-Flight Sloj (Cleanup & Push)"]
        PUSH["Sync-ServiceHub.ps1 -Push"]
        CLEAN["Protect-USBIntegrity.ps1 -AutoClean"]
    end

    BAT --> PS1
    PS1 --> PROT
    PROT --> WP
    WP --> SANDBOX
    PS1 --> DEV
    DEV --> DEVICES
    PS1 --> SYNC
    SYNC --> UDP
    SYNC -.-> QUEUE
    PS1 --> CLI
    CLI --> PROMPT
    CLI --> SKILLS
    CLI --> PUSH
    PUSH --> CLEAN
```

---

## 🔄 3. Tok Podataka (Data Flow)

```mermaid
sequenceDiagram
    autonumber
    actor Tech as Serviser
    participant USB as USB Medijum (Start-ServisAI)
    participant Client as Klijent PC (Windows 10/11)
    participant Hub as Servis Hub (:8000 / :8888)
    participant Cloud as Google Cloud (Gemini API)

    Tech->>USB: Pokreće Start-ServisAI.bat
    USB->>Client: UAC Elevacija & postavljanje bafera (9000 linija)
    USB->>Client: Očitavanje serijskog broja i hardvera (CIM)
    Client-->>USB: Vraća identifikovan DeviceTag
    USB->>Hub: UDP Auto-Discovery (:8888) -> GET /api/devices/{tag}/history
    Hub-->>USB: Ranija istorija intervencija (Pre-flight Pull)
    USB->>Cloud: Povezivanje agy.exe (Headless OAuth)
    Tech->>USB: Dijagnostički upiti (/smart-health, /event-log-triage...)
    USB->>Client: Izvršavanje sigurnih PowerShell skripti
    Client-->>USB: Sirova telemetrija i logovi
    USB->>Cloud: Analiza i Root-Cause sinteza
    Cloud-->>USB: Sažet zaključak i preporuke
    USB->>USB: Snimanje reports/IZVESTAJ_DIJAGNOSTIKE.md
    USB->>Hub: POST /api/devices/{tag}/agy-session (Post-flight Push)
    alt Ako je Hub nedostupan
        USB->>USB: Odlaganje paketa u pending_sync/*.json
    end
    USB->>USB: Završno samočišćenje od virusa (-AutoClean)
```

---

## 📚 4. Povezane Beleške i Dokumentacija
- [[index]] — Glavni MOC navigacioni indeks
- [[decisions/ADR-0001-portable-usb-architecture]] — Arhitektura prenosivog USB CLI agenta
- [[decisions/ADR-0002-hardware-write-protect-and-device-fingerprint]] — Hardverska identifikacija i zaštita od upisa
- [[decisions/ADR-0003-servis-hub-bidirectional-sync]] — Dvosmerna integracija sa Servis Hub-om
- [[domain/glossary]] — Rečnik domena i tehnički pojmovnik
- [[memory/gotchas]] — Rešeni problemi, bagovi i inženjerski trikovi
- Glavna tehnička dokumentacija: `TEHNICKA_DOKUMENTACIJA.md`
- Servisno uputstvo za tehničare: `UPUTSTVO_ZA_KORISCENJE.md`
