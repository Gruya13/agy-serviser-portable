---
title: "ADR-0003: Dvosmerna Sinhronizacija sa Servis Hub-om, UDP Auto-Discovery i Offline Red"
type: decision
status: accepted
created: 2026-10-09
updated: 2026-10-09
tags:
  - adr
  - decision
  - architecture
  - servis-hub
  - udp-discovery
  - sync
  - offline-queue
---

# ADR-0003: Dvosmerna Sinhronizacija sa Servis Hub-om, UDP Auto-Discovery i Offline Red

## 1. Kontekst i Problem
U servisnoj radionici, više servisera koristi zasebne prenosive USB fleševe. Podaci zabeleženi na jednom USB-u ostajali su izolovani. Prilikom ponovnog prijema računara na servis, serviser nije imao uvid u prethodne intervencije kolega. Takođe, otkaz USB medijuma nosi rizik trajnog gubitka lokalnih evidencija.

## 2. Razmatrane Opcije
- **Opcija A: Deljeni mrežni disk (SMB share) sa centralnim fajlovima:** Zahteva stalnu mrežnu konekciju, sporo je na Wi-Fi mreži i puca na terenu van radionice.
- **Opcija B: Hibridni model sa UDP Auto-Discovery, REST API-jem i Offline redom [PRIHVAĆENO]:**
  - **Mrežno pronalaženje:** Automatska detekcija Servis Hub-a putem UDP broadcast upita na portu 8888, uz rezervni statički URL iz `config/settings.json`.
  - **Pre-flight Pull:** Pre pokretanja AI sesije, klijent poziva `GET /api/devices/{tag}/history` (ili po serijskom broju). Prikazuje istoriju ranijih intervencija u konzoli i prosleđuje kontekst agentu.
  - **Post-flight Push:** Po završetku rada, klijent šalje strukturirani JSON paket na `POST /api/devices/{tag}/agy-session` (hardver, unosi u dnevnik, dijagnostički izveštaj, Root-Cause sažetak).
  - **Offline tolerancija:** Ako Hub nije dostupan, podaci se bez pucanja odlažu u `pending_sync/*.json` i automatski prazne (`Auto-Flush`) pri prvoj sledećoj sesiji.

## 3. Doneta Odluka
Implementirani su moduli:
- `scripts/Sync-ServiceHub.ps1` na klijentu (PowerShell klijent sa podrškom za `-Pull`, `-Push`, `-FlushPending`).
- Proširenje `servishub` REST API-ja i telemetrijskog sistema na serveru Servis Hub.
- Integracija u `Start-ServisAI.ps1` u Pre-flight fazi i Post-flight `finally` bloku.
- E2E integracioni testovi u `tests/test_e2e_sync.py` (6/6 scenarija uspešno prošlo).

## 4. Posledice i Status
- **Pozitivne:** Serviseri u radionici odmah vide šta je ko radio na računaru; centralna baza je uvek ažurna; puni rad bez zastoja i na terenu van dometa radionice.
- **Negativne:** Zahteva rad Servis Hub servera na lokalnoj mreži za funkciju Auto-Discovery mehanizma.
