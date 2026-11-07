---
title: "ADR-0004: Pre-Flight Auto-Registracija, Kontekstni Izvodi i In-Flight Checkpoint Sinhronizacija"
type: decision
status: accepted
created: 2026-10-10
updated: 2026-10-10
tags:
  - adr
  - decision
  - architecture
  - servis-hub
  - pre-flight-registration
  - context-ingestion
  - live-checkpoint
  - offline-queue
---

# ADR-0004: Pre-Flight Auto-Registracija, Kontekstni Izvodi i In-Flight Checkpoint Sinhronizacija

## 1. Kontekst i Problem
U prethodnoj implementaciji (ADR-0003), klijent je u Pre-flight fazi proveravao postojanje servisne istorije, ali su postojala tri ključna ograničenja:
1. **Nedostatak direktnog kontekstnog fajla za AI asistenta:** Preuzeta istorija prikazivala se u konzoli PowerShell-a, ali sam Antigravity AI CLI agent nije imao generisan strukturisani fajl istorije unutar svog radnog prostora (`--add-dir devices/<DeviceTag>`).
2. **Nepostojanje pre-flight evidencije za nove računare:** Ako računar nikada ranije nije bio evidentiran, centralni Servis Hub je saznavao za njega tek na kraju dijagnostike (Post-flight Push). Ako je sesija prekinuta ili se dijagnostika oduži, Servis Hub nije imao informaciju da je računar na servisu.
3. **Rizik od gubitka nalaza pre završetka sesije:** Ako se nestabilan računar naglo ugasi usled hardverskog kvara (BSOD, pregrevanje, pad napona), nalazi otkriveni tokom rada ostajali su nesačuvani na Hub-u.

## 2. Donete Odluke i Arhitektura

### 2.1 Pre-Flight Izvlačenje Istorije i Spajanje Dnevnika (`SERVIS_HUB_HISTORY.md`)
- Kada `Sync-ServiceHub.ps1 -Pull` preuzme istoriju sa Hub-a:
  - Automatski generiše pregledan Markdown dokument `devices/<DeviceTag>/SERVIS_HUB_HISTORY.md` sa hronologijom ranijih intervencija, Root-Cause nalazima, zamenjenim delovima i parametrima garancije.
  - Sprovodi inteligentno spajanje (Merge) unosa dnevnika sa Hub-a u lokalni `SERVISNI_DNEVNIK.md` bez dupliranja i bez brisanja lokalnih novijih unosa.
  - Implementira fallback pretragu: ukoliko računar nije pronađen po `DeviceTag`-u, automatski ga traži po serijskom broju preko `/api/devices/by-serial/{serial}/history`.

### 2.2 Automatska Pre-Flight Registracija Novog Uređaja
- Ako uređaj ne postoji na Hub-u (`is_registered: false`):
  - Klijent odmah, pre startovanja AGY CLI sesije, poziva `POST /api/devices/{tag}/register` (putem `Sync-ServiceHub.ps1 -Register`).
  - Šalje hardverski profil, serijski broj, datum prijema i postavlja status `U_DIJAGNOSTICI`.
  - Servis Hub odmah otvara novi digitalni karton (`DEVICE_INFO.json`) i inicijalizuje `SERVISNI_DNEVNIK.md`.
  - Ako je računar offline, paket se bez pucanja smešta u `pending_sync/<timestamp>_REGISTER_<tag>.json` i šalje naknadno.

### 2.3 In-Flight Perzistencija i Live Checkpoints (`Save-ServiceProgress.ps1`)
- Uvedena je namenska servisna skripta `scripts/Save-ServiceProgress.ps1` (i parametar `-Checkpoint` u `Sync-ServiceHub.ps1`).
- Agent u toku rada (čim otkrije loš SMART sektor, oštećen drajver ili BSOD uzrok) poziva ovu skriptu.
- Skripta upisuje nalaz u lokalni `SERVISNI_DNEVNIK.md` i šalje paket na `POST /api/devices/{tag}/checkpoint`.
- Status uređaja na centralnom radioničkom ekranu Servis Hub-a odmah se ažurira (npr. u `Kvar (AGY)` / `KVAR_POTVRDJEN`).

### 2.4 Offline Tolerancija i Auto-Flush
- Svi paketi (`REGISTER`, `CHECKPOINT`, `SESSION`) podržani su u `pending_sync/` redu čekanja.
- Metoda `Invoke-HubFlushPending` prepoznaje tip paketa po prefiksu i rutira ga na odgovarajući API endpoint čim se uspostavi veza.

## 3. Posledice
- **Pozitivne:**
  - AI asistent odmah prepoznaje recidivne kvarove i prethodne radove kolega čim se sesija pokrene.
  - Radionica u realnom vremenu vidi koji su računari na prijemu i u kakvom su statusu.
  - Podaci su zaštićeni od naglog gašenja računara zahvaljujući live checkpoint mehanizmu.
  - 100% pokrivenost realnim E2E testovima (11/11 uspešnih scenarija bez ikakvih mock-ova).
