---
title: "ADR-0001: Arhitektura Prenosivog Antigravity CLI USB Asistenta"
type: decision
status: accepted
created: 2026-09-10
updated: 2026-10-09
tags:
  - adr
  - decision
  - architecture
  - portable-usb
  - headless-oauth
---

# ADR-0001: Arhitektura Prenosivog Antigravity CLI USB Asistenta

## 1. Kontekst i Problem
Za potrebe računarskog servisa na terenu i u radionici, potreban je inteligentni dijagnostički asistent sposoban da brzo analizira hardverske i softverske probleme na klijentskim mašinama pod Windows 10 i Windows 11 operativnim sistemima.
Desktop verzija Antigravity 2.0 zahteva instalaciju u sistem, teške GUI biblioteke i zauzima značajne resurse. Takođe, standardni veb pregledač na klijentu nosi rizik krađe lozinki servisera ako bi se prijava vršila u klijentskom browseru.

## 2. Razmatrane Opcije
- **Opcija A: Antigravity 2.0 Desktop Aplikacija:** Zahteva instalaciju, ne može se pokretati u portable režimu sa zaključanog USB-a, troši previše RAM-a na slabijim mašinama.
- **Opcija B: Samostalni Python / PowerShell skriptovi sa plaćenim API ključem:** Donosi visoke troškove po utrošku tokena, osetljivi API ključevi moraju se čuvati na prenosivom medijumu.
- **Opcija C: Antigravity CLI (`agy.exe`) sa Headless Remote OAuth autorizacijom [PRIHVAĆENO]:**
  - Samostalni Go binarni fajl bez zavisnosti (nema Python/Node.js instalacije na klijentu).
  - Korišćenje postojeće Google AI Pro pretplate bez plaćanja dodatnih API troškova.
  - Headless OAuth: Generisanje URL koda koji serviser otvara na svom telefonu. Klijent nikada ne vidi lozinku.

## 3. Doneta Odluka
Usvaja se rešenje bazirano na zvaničnom Antigravity CLI (`bin/agy.exe`) uz pokretanje preko `Start-ServisAI.bat` i `Start-ServisAI.ps1`.
Sve konfiguracije, sistemska uputstva (`AGENTS.md`) i veštine nalaze se na USB flešu.

## 4. Posledice i Status
- **Pozitivne:** Trenutan start na bilo kom Windows 10/11 računaru; nula instalacija; potpuna zaštita serviserevog Google naloga; nula dodatnih API troškova.
- **Negativne:** Za rad je neophodna aktivna internet konekcija radi komunikacije sa Gemini modelima.
