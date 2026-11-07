---
title: "Početni Indeks Znanja (Map of Content)"
type: index
created: 2026-10-09
updated: 2026-10-09
tags:
  - moc
  - index
  - wiki
---

# Početni Indeks Znanja: AGY Serviser Portable

Dobrodošli u centralnu bazu znanja i dugoročnu Obsidian memoriju projekta **AGY Serviser Portable** (Antigravity CLI Portable).

---

## 🗺️ Mape Sadržaja (Navigacija)

### 1. 🏛️ Arhitektura Sistema (`architecture/`)
- [[architecture/overview]] — Šestoslojni model, tokovi podataka, integracija i bezbednost.

### 2. 📋 Arhitektonske Odluke (`decisions/`)
- [[decisions/ADR-0001-portable-usb-architecture]] — Arhitektura prenosivog USB CLI agenta i headless autorizacija.
- [[decisions/ADR-0002-hardware-write-protect-and-device-fingerprint]] — Hardverska identifikacija, Write-Protect i separacija po uređajima.
- [[decisions/ADR-0003-servis-hub-bidirectional-sync]] — Dvosmerna integracija sa Servis Hub-om, UDP discovery i offline red.
- [[decisions/ADR-0004-preflight-registration-and-live-checkpoint]] — Pre-flight auto-registracija, kontekstni izvodi i in-flight checkpoint sinhronizacija.

### 3. 📖 Domen i Rečnik (`domain/`)
- [[domain/glossary]] — Rečnik stručnih pojmova, skraćenica i definicija u servisu.

### 4. 🧠 Memorija i Zamke (`memory/`)
- [[memory/gotchas]] — Evidencija uočenih problema, bagova (conhost, chcp, generički serijski brojevi) i rešenja.

### 5. 📑 Šabloni (`templates/`)
- [[templates/template-adr]] — Šablon za novu arhitektonsku odluku.
- [[templates/template-concept]] — Šablon za opis novog koncepta.
- [[templates/template-gotcha]] — Šablon za veći izolovani problem.
- [[templates/template-task]] — Šablon za izveštaj o završenom zadatku.

---

## 📂 Spoljna Projektna Dokumentacija
- [`TEHNICKA_DOKUMENTACIJA.md`](../TEHNICKA_DOKUMENTACIJA.md) — Glavni, sveobuhvatni tehnički referentni priručnik sistema.
- [`UPUTSTVO_ZA_KORISCENJE.md`](../UPUTSTVO_ZA_KORISCENJE.md) — Servisni priručnik za rad tehničara na terenu.
- [`README.md`](../README.md) — Brzi vodič i sažetak projekta.
- [`istorija_izrade.md`](../istorija_izrade.md) — Hronološki dnevnik izmena i implementacija.
