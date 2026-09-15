# Changelog — GDC Firewall

Formatul urmează versionarea semantică (Regula 14 din Standardul GDC).

## v0.1.0 (2026-09-15) — Schelet inițial

### Added
- Strat de interfață SwiftUI complet, separat de motorul LuLu (care rămâne
  vendorat neschimbat, `Engine/LuLu/`).
- Fereastră de alertă redesenată: insignă circulară de risc (semafor
  verde/galben/roșu), explicație în română, recomandare vizibilă, detalii
  tehnice ascunse într-un disclosure.
- `ProcessDictionary.json` — mapare locală proces → explicație în română
  (20 de intrări inițiale), extensibilă fără recompilare.
- Mod Silențios (Aprobare inteligentă), **activat implicit**: aprobă tăcut
  doar procesele semnate oficial de Apple, cu jurnal vizibil.
- Rules Manager glassmorphic, pe categorii (`Aplicații Verificate`,
  `Servicii Sistem`, `Reguli Blocate`), cu pictogramă, nume intuitiv,
  insignă de conexiune și comutator per aplicație.
- Modul „Filtrare & AdBlock”: liste StevenBlack, trei nivele cumulative
  (Minim / Mediu / Maxim), comutator independent per nivel, buton
  „Actualizare liste”, cache local de hash-uri FNV-1a în memorie, listă de
  excepții controlată de utilizator.
- Selector de temă Sistem/Light/Dark, mutare automată în `/Applications`,
  Update Checker pe `update.json` + self-updater (Regulile 13, 18, 20).
- `docs/` pentru GitHub Pages pe `gordas.dev/gdc-firewall`.

### Changed
- **Corecție de arhitectură**, după citirea sursei LuLu v4.5.1: puntea XPC a
  fost rescrisă pe contractul real (`XPCDaemonProto.h` / `XPCUserProto.h`).
  Alertele sosesc prin `alertShow:reply:` (daemon → aplicație), nu sunt
  cerute; `getRules:` întoarce o arhivă de obiecte `Rule`, nu dicționare;
  serviciul Mach e prefixat cu Team ID. Consecință: aplicația se
  construiește ca înlocuitor al țintei `LuLu/App`, nu ca aplicație separată
  lângă un LuLu oficial — vezi CLAUDE.md, Partea 2.
- Tag-ul motorului fixat la `v4.5.1` (`v2.9.0` nu există în upstream).

### Notes
- Paritatea Mac/Windows (Regula 31) nu se aplică: produsul e legat
  structural de NetworkExtension pe macOS.
- Produsul e GPL-3.0 fiindcă motorul e GPL-3.0; atribuirea Objective-See e
  obligatorie (`NOTICE.md`).
