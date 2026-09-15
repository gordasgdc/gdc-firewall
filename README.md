# GDC Firewall

Firewall pentru macOS, **în română**, gândit pentru oameni care nu sunt
tehnici. Aceeași protecție ca un firewall clasic, dar fără jargon: în loc de
„`cloudd` wants to connect to `17.248.146.12:443`”, aplicația spune
*„Serviciul Apple iCloud vrea să se conecteze la internet — sincronizează
fișierele și datele tale cu iCloud.”*

Gratuit, fără licențiere, fără cont. Sursă publică, GPL-3.0.

## Ce face

- **Alerte cu semafor.** Fiecare cerere de conexiune primește o insignă
  circulară: 🟢 semnat oficial de Apple, 🟡 dezvoltator identificat,
  🔴 neidentificat. Recomandarea e scrisă explicit sub butoane.
- **Mod Silențios (Aprobare inteligentă), activat implicit.** Serviciile
  semnate de Apple sunt aprobate tăcut și trec într-un jurnal vizibil, nu
  într-un pop-up. Tot ce nu e Apple te întreabă în continuare.
- **Rules Manager** cu efect de sticlă mată, împărțit pe
  `Aplicații Verificate` / `Servicii Sistem` / `Reguli Blocate`.
- **Filtrare & AdBlock** pe liste StevenBlack, cu trei nivele:
  Minim (malware, phishing, telemetrie) · Mediu (+ reclame și urmărire) ·
  Maxim (+ pornografie și pariuri). Filtrarea rulează local, în memorie.
- **Actualizare automată** prin `update.json` pe gordas.dev.

## Motor

Filtrarea propriu-zisă e făcută de [LuLu](https://github.com/objective-see/LuLu)
(© Objective-See), vendorat neschimbat în `Engine/LuLu/`. Stratul GDC nu
atinge extensia de rețea și nu conține logică de kernel — vezi `NOTICE.md`.

## Construire

```bash
./scripts/fetch-engine.sh      # aduce motorul LuLu la tag-ul fixat
cd macOS/GDCFirewall && swift build
```

Pachetul semnat + notarizat se face cu `./scripts/build_app.sh`.

> **Blocaj de cont, nu de cod:** extensia de rețea are nevoie de
> entitlement-ul `com.apple.developer.networking.networkextension`
> (`content-filter-provider`), pe care Apple îl acordă doar la cerere
> explicită pe contul Developer. Fără el, build-ul semnat pornește, dar
> extensia nu se încarcă.

## Licență

GPL-3.0. © 2026 Cristi Gordaș / GDC. Motor: LuLu © Objective-See.
