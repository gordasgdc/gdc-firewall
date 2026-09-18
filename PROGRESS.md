# Stare proiect — GDC Firewall

**Ultima actualizare:** 2026-09-18 · **Versiune:** 2.2.0 · **Ramură:** `main`

---

## Pe scurt

Pachetul **v2.0.0 este stabil și compilabil**. Toate cele trei ținte se
construiesc curat: pachetul SPM (harnașamentul de interfață), aplicația și
extensia de rețea, ambele în Release.

**Singurul pas rămas pentru vineri: trimiterea formularului de entitlement
către Apple.** Textele sunt scrise și gata de copiat în
`macOS/GDCFirewall/codesigning/apple-entitlement-request.md`. Formularul se
completează din contul Developer al lui Cristi (Team ID `8AR6XP8MG7`) — nu
poate fi trimis de altcineva, iar răspunsul vine pe e-mailul contului.

---

## Ce e gata

| Zonă | Stare |
|---|---|
| Interfață SwiftUI (alertă semafor, Rules Manager, Auto-Pilot, temă) | gata |
| Filtrare de domenii, 3 nivele StevenBlack, cache local de hash-uri | gata |
| Integrare în workspace-ul motorului LuLu v4.5.1 | gata, ambele ținte compilează |
| Actualizare hibridă (interfață + motor) | gata |
| Pictogramă, din sursă vectorială | gata |
| Ghid `Instructiuni_Utilizare.pdf`, RO/EN/ES, 12 pagini, generat din `installer/generate-guide.swift` | gata |
| Interfață RO/EN/ES, verificată de `scripts/check-l10n.sh` | gata |
| Scripturi: build, integrare, verificare, sincronizare site | gata |
| Documentație de semnare + checklist de notarizare | gata |
| Distribuție sincronizată în `gdc-plugin-manager-catalog-vendor/docs/gdc-firewall/` | gata (v2.0.0 comisă) |

## Ce NU e gata, și de ce

1. **Profilele Developer ID** — două, create în portalul Apple
   (pașii îi tipărește `scripts/build_engine_app.sh`). Fără ele, build-ul
   complet semnat nu pornește. Probabil nu mai e nevoie de cererea separată
   de entitlement: Network Extensions se bifează direct pe App ID.
2. **Semnare reală și notarizare** — depind de punctul 1. Până atunci
   build-urile sunt ad-hoc, bune pentru testarea interfeței, nu a filtrării.
3. **Test manual pe un Mac real** — instalare, aprobarea extensiei din Setări
   de sistem, o alertă reală. Nicio verificare automată nu acoperă pașii
   aceștia; vezi secțiunea 6 din `codesigning/README-notarizare.md`.
4. **Publicarea v2.0.1 pe gordas.dev** — `build_app.sh` + `sync-site.sh`,
   apoi commit + push în `gdc-plugin-manager-catalog-vendor`. Până atunci
   site-ul servește 2.0.0 cu vechiul link `.pkg` (404), inofensiv cât timp
   nu anunță o versiune mai nouă decât cea instalată.

---

## Problemă deschisă

**Actualizarea extensiei lasă daemon-ul fără serviciu XPC până la repornire.**
Versiunea nouă pornește înainte ca cea veche să elibereze serviciul Mach, iar
motorul nu reîncearcă. Între timp filtrul permite tot, fără alerte. De decis:
aplicația detectează situația și cere repornirea Mac-ului, sau altă strategie
de înlocuire.

## Reluare — de unde continui

```bash
cd ~/Developer/gdc-firewall
./scripts/verify-engine-build.sh      # reintegrează + compilează ambele ținte
```

Dacă `Engine/LuLu/` lipsește (nu e urmărit de git), `fetch-engine.sh` îl
aduce, iar `integrate-engine.sh` reaplică integrarea. Ambele rulează singure
din scriptul de mai sus.

**După aprobarea Apple**, în ordine:

1. Regenerează profilul de semnare; capabilitatea se acordă pe App ID, deci
   trebuie activată pe **amândouă**: `dev.gordas.GDCFirewall` și
   `dev.gordas.GDCFirewall.extension`.
2. Exportă `APPLE_SIGN_IDENTITY_APP` / `APPLE_SIGN_IDENTITY_INSTALLER` și
   rulează `./scripts/build_app.sh`. Scriptul verifică singur că
   entitlement-ul a ajuns în binarul semnat și se oprește dacă lipsește.
3. Parcurge `codesigning/README-notarizare.md`, de la capăt.

---

## Lucruri de reținut înainte de a atinge codul

- **Versiunea nu coboară sub 2.0.0.** `Extension/XPCListener.m` acceptă doar
  clienți cu `CFBundleShortVersionString >= "2.0.0"`, iar extensia nu se
  modifică. Saltul de la 0.1.0 a fost impus de motor, nu ales.
- **`Engine/LuLu/` nu e în git.** Orice editare manuală acolo se pierde la
  următorul `fetch-engine.sh`. Modificările trăiesc în
  `scripts/integrate-engine.sh`.
- **Extensia de rețea e intangibilă.** `fetch-engine.sh` oprește build-ul la
  orice `.m`/`.h` schimbat în `LuLu/Extension/`. `Info.plist` și
  `Extension.entitlements` sunt excepții numite — identitate, nu comportament.
- **Un fișier Swift nou nu intră singur în ținta Xcode.** Lista de surse e un
  instantaneu luat la integrare, iar `swift build` rămâne verde fiindcă SPM
  vede folderul, nu proiectul. Rulează `verify-engine-build.sh`, care
  reintegrează întâi.
- **`--deep` nu se folosește la semnare.** Aplicația și extensia au
  entitlements diferite; `--deep` le-ar aplica pe ale aplicației peste
  extensie, iar macOS ar refuza s-o încarce fără să spună de ce.
