# Changelog — GDC Firewall

Formatul urmează versionarea semantică (Regula 14 din Standardul GDC).

## v2.1.0 (2026-09-18) — Import din LuLu și Little Snitch, filtru finalizat

### Added
- **Configurare inițială** (o singură dată, doar dacă găsește alte
  firewall-uri; redeschisă din meniu): detectează Little Snitch și LuLu și
  starea lor reală, importă regulile lor și arată exact de unde le oprește
  utilizatorul — macOS nu permite unei aplicații să oprească filtrul altui
  producător.
- **Import LuLu**: citește direct `/Library/Objective-See/LuLu/rules.plist`,
  doar regulile create de utilizator; sare regulile dezactivate, expirate,
  valabile doar pe durata unui proces și pe cele ale aplicațiilor absente.
- **Import Little Snitch**: `littlesnitch export-model` prin promptul nativ
  de parolă de administrator, sau un fișier `.lsrules`/JSON ales manual.
  Domeniile devin regex (domeniu + subdomenii), adresele CIDR rămân CIDR.
  Ce nu are echivalent în motor (intrare, „via”, „întreabă”, intervale de
  porturi/adrese, destinații speciale) se sare și se numără — o regulă nu e
  niciodată lărgită (un „blochează intervalul X” nu devine „blochează tot”).
- Comutator „Filtrare activă” în meniu. O oprire făcută de utilizator (meniu
  sau Setări → Rețea → Filtre) se respectă și la relansare.
- Meniul cere repornirea Mac-ului când filtrul rulează, dar daemon-ul e de
  negăsit după 5 reconectări (cazul înlocuirii extensiei la actualizare).

### Fixed
- **Daemon-ul GDC folosea folderul LuLu** (`/Library/Objective-See/LuLu`):
  citea și scria regulile unui LuLu real de pe același Mac. Acum
  `/Library/Application Support/GDC Firewall`; build-ul verifică asta.
- Fereastra Reguli era mereu goală: `decodeRules` presupunea structura
  `{ cale: [Rule] }`, cea reală e `{ cheie: { rules, signingInfo, paths } }`.
- Ștergerea unei reguli trimitea calea în locul cheii motorului.
- Dezinstalatorul șterge și datele motorului (cere parola de administrator).

### Known issues
- Formatul exact al `littlesnitch export-model` nu a putut fi verificat
  (cere root); parserul urmează formatul public `.lsrules`. Testat pe un
  fișier `.lsrules` de probă și pe regulile LuLu reale, nu pe un export
  Little Snitch real.
- Ghidul PDF nu descrie încă fereastra de configurare inițială (Regula 8).

## v2.0.4 (2026-09-18) — Aplicația se conectează la daemon

### Fixed
- Meniul rămânea pe „Motor oprit” cu filtrul pornit: `LuLuConstants.swift`
  păstrase valorile upstream (`VBG97UB4TA.com.objective-see.lulu`), iar
  extensia integrată ascultă pe `8AR6XP8MG7.dev.gordas.GDCFirewall`.
  Aplicația căuta un serviciu Mach care nu există.

- După o întrerupere (extensie înlocuită la update, daemon repornit, sleep)
  aplicația nu se mai reconecta niciodată. Acum reîncearcă singură, cu
  așteptare crescătoare de la 2 s la 60 s.

### Added
- Log de diagnostic în `DaemonBridge` (Regula 25): invalidare, întrerupere,
  apeluri XPC eșuate, rezultatul `checkIn`.
- `build_engine_app.sh` verifică că serviciul Mach din binarul aplicației e
  exact `NEMachServiceName` al extensiei construite.

## v2.0.3 (2026-09-18) — Filtrul de rețea chiar pornește

### Fixed
- Extensia ajungea „activated enabled”, dar procesul ei nu pornea: filtrul
  (`NEFilterManager`) nu era configurat nicăieri — logica trăia în
  `App/Extension.m` al motorului, scos din țintă. Portată în
  `SystemExtensionInstaller`: filtrare pe socket-uri, fără pachete, numele
  „GDC Firewall” în Setări → Rețea → Filtre. Refuzul promptului de filtrare
  apare în meniu ca eroare.

## v2.0.2 (2026-09-18) — Aplicația completă pornește și cere extensia

### Fixed
- Build-ul complet (cu motorul) se închidea instant la pornire: Info.plist-ul
  motorului cerea clasa principală `NSApplicationKeyEvents`, scoasă din țintă
  odată cu interfața LuLu. Acum `NSApplication`.
- Activarea extensiei nu era apelată nicăieri: extensia nu ajungea la macOS,
  nu apărea în Setări și nu cerea aprobare. Se cere acum la pornire.
- `NSSupportsAutomaticTermination` oprit: aplicația din bara de meniu nu mai
  poate fi închisă de sistem cât așteaptă alerte de la daemon.

### Added
- Starea extensiei în meniu: „Se activează…”, „Aprobă extensia în Setări de
  sistem”, sau motivul eșecului, în loc de un „Motor oprit” generic.
- `build_engine_app.sh` verifică existența clasei principale în binar.

## v2.0.1 (2026-09-18) — Actualizare automată din arhiva .zip, build cu Xcode 27

### Fixed
- `update.json` indica `releases/latest/download/GDCFirewall.pkg`, care dă
  404 (nu există release GitHub și nici `.pkg`). Linkul duce acum la arhiva
  `https://gordas.dev/gdc-firewall/GDCFirewall-macOS.zip`.
- `SelfUpdater` înțelege acum și `.zip`: dezarhivează, verifică versiunea
  din arhivă față de cea anunțată și înlocuiește aplicația pe loc. Înainte,
  orice descărcare ajungea la `installer -pkg`.
- Relansarea după update folosea `open -a "GDCFirewall"`, dar bundle-ul se
  numește „GDC Firewall.app” — acum `open -b <bundle id>`.
- Pagina de rezervă la eșecul update-ului era release-ul GitHub (gol); acum
  e `gordas.dev/gdc-firewall/`.
- Build-ul picase cu Xcode 27 (minim acceptat macOS 12): ținta extensiei
  primește același minim ca aplicația, macOS 13. Doar setare de build;
  sursele `Extension/` rămân neatinse.

### Known issues
- Instalările 2.0.0 au vechiul `SelfUpdater`, care trimite orice fișier la
  `installer -pkg`: nu se pot actualiza singure din `.zip`. Update manual,
  de pe gordas.dev, o singură dată.

## v2.0.0 (2026-09-15) — Integrare cu motorul, actualizare hibridă, ghid trilingv

### Added
- Integrare reală în workspace-ul motorului: `scripts/integrate-engine.sh`
  rescrie ținta „App” ca ținta GDC Firewall. Ambele ținte compilează.
- Activarea extensiei de sistem, cu stare vizibilă în interfață
  (`SystemExtensionInstaller.swift`).
- Actualizare hibridă: manifestul poartă `app_version` și
  `engine_version_required`; actualizarea se oferă dacă oricare dintre ele
  e depășită. Motorul nesusținut produce un pop-up critic, fără „Mai târziu”.
- Mesajul de actualizare critică, tradus RO/EN/ES (`Localization.swift`).
- `installer/generate_pdf.py` — ghid trilingv de 9 pagini, cu pasul critic
  de aprobare a extensiei de rețea explicat în toate cele trei limbi.
- `codesigning/sign-and-notarize.sh`, `README-notarizare.md` (checklist) și
  `apple-entitlement-request.md` (textele pentru formularul Apple).

### Changed
- **Versiunea sare de la 0.1.0 la 2.0.0.** Nu e o decizie de produs:
  `Extension/XPCListener.m` acceptă doar clienți cu
  `CFBundleShortVersionString >= 2.0.0`, iar extensia nu se modifică.
- Minimul aplicației urcă la macOS 13 (`MenuBarExtra`, scena `Window`).
  Extensia rămâne cu ținta ei originală.
- `fetch-engine.sh` verifică acum exact ce trebuie — orice `.m`/`.h` din
  `Extension/` — în loc de orice diferență față de upstream.

### Fixed
- `Bundle.module` nu există în afara SPM; resursa se rezolvă la compilare.
- Lista de surse a țintei Xcode e un instantaneu luat la integrare: un fișier
  Swift nou nu intră singur în ea, iar `swift build` rămâne verde fiindcă el
  vede folderul, nu proiectul. `scripts/verify-engine-build.sh` reintegrează
  înainte de fiecare verificare, ca drift-ul să nu mai poată apărea.

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

### Added (continuare)
- Pictograma aplicației: sursă vectorială unică `Resources/AppIcon.svg`
  (scut geometric amber/cupru pe placă închisă, aceeași glifă ca antetul
  paginii de prezentare), plus `scripts/make-appicon.sh` care o exportă în
  toate dimensiunile macOS și scrie `Contents.json` din aceeași listă.

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
