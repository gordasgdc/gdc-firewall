# Changelog — GDC Firewall

Formatul urmează versionarea semantică (Regula 14 din Standardul GDC).

## v2.3.4 (2026-09-20) — Instalare din DMG notarizat, ghid de aprobare a extensiei

### Changed
- Distribuția e acum o imagine **DMG** semnată Developer ID, notarizată și stapled (în locul arhivei .zip, blocată de browsere ca „suspectă”). Conține aplicația, un link către Aplicații și ghidul PDF.
- Actualizarea automată știe să instaleze din DMG.

### Added
- Când extensia de rețea așteaptă aprobarea, aplicația arată un ghid la pornire și un buton în meniu care deschide direct Setări de sistem → Confidențialitate și securitate.

## v2.3.3 (2026-09-19) — Mutare în Aplicații fiabilă, dezinstalare completă, arhivă versionată

### Fixed
- **Mutarea în Aplicații pentru arhivele descărcate din browser.** Cauza,
  reprodusă: browserul marchează arhiva pentru izolare (App Translocation),
  iar marcajul se păstra pe copia din `/Applications` — aplicația pornea tot
  izolată, cerea mutarea din nou, iar a doua mutare ducea copia instalată la
  Coș. Acum copia din Aplicații rulează pe loc (carantina rămâne, Gatekeeper o
  verifică în continuare), o instalare deja izolată se repară singură, iar
  aplicația nu mai copiază niciodată peste ea însăși.
- Promptul de mutare apare în față: aplicația de bara de meniu nu are
  fereastră, iar alerta putea rămâne ascunsă în spatele altor ferestre.
- Orice altă cale decât `/Applications/GDC Firewall.app` (alt nume,
  `~/Applications`, Descărcări) e detectată; instanțele deja pornite se
  închid înainte de relansare.

### Changed
- **Dezinstalatorul** funcționează oriunde s-ar afla aplicația (sau fără ea):
  găsește toate copiile după identificator, oprește filtrul de rețea prin
  aplicație (`--uninstall-extension`, promptul nativ macOS), scoate
  configurația de filtru, regulile, preferințele, logurile, apoi verifică ce
  a rămas. `--dry-run` arată ce ar face.
- **Arhiva de pe site poartă versiunea în nume** (`GDCFirewall-macOS-2.3.3.zip`):
  butonul paginii și `update.json` duc la ea; copia cu nume stabil rămâne.

## v2.3.2 (2026-09-18) — Înlocuirea extensiei fără repornirea Mac-ului

### Fixed
- **Cursa de înlocuire a extensiei** (problema deschisă din v2.0.4). Cauza,
  din logul launchd: la înlocuire, extensia nouă e înregistrată cât timp jobul
  vechi încă există, iar launchd îi scoate serviciul Mach din definiție — nu
  se mai putea conecta nicio interfață până la repornirea Mac-ului.
  Reparația, verificată pe Mac-ul real: **înlocuire secvențială** — jobul
  vechi se oprește ÎNAINTE de activarea celui nou.
  - instalare manuală peste o versiune care rulează: o singură parolă de
    administrator; „Anulează” amână actualizarea motorului (aplicația
    folosește filtrul vechi, meniul oferă „Finalizează actualizarea
    motorului…”), fără nicio buclă de prompturi;
  - actualizarea automată o face în scriptul ei, care rulează deja ca root —
    fără parolă în plus;
  - dacă o versiune mai veche a aplicației a produs totuși cursa: un singur
    mesaj „Repornește Mac-ul…” (singura reparație reală; `kickstart` și
    `bootout` pe jobul nou au fost testate și NU repară).
- **Garda de actualizare**: pe durata înlocuirii, motorul blochează
  conexiunile necunoscute (regulile existente se aplică); preferințele
  anterioare se refac la conectarea cu extensia nouă, inclusiv după un crash.
- **Mutare în Aplicații**: pornită din altă parte (ex. Downloads, inclusiv
  sub App Translocation), aplicația oferă „Mută în folderul Aplicații”, se
  copiază, se relansează din `/Applications` și duce originalul la Coș. O
  copie veche deținută de root cere parola de administrator. `~/Applications`
  nu mai e acceptat: macOS nu activează extensia de rețea de acolo.

### Added
- `scripts/cleanup_competing_firewalls.sh` — curățare Little Snitch + LuLu
  (la Coș, recuperabil; GDC Firewall exclus și verificat la final).
- `scripts/engine-status.sh` — starea motorului, fără root.

## v2.3.1 (2026-09-18) — Layout bară laterală, Setări la vedere, prima arhivă notarizată

### Fixed
- Butoanele de fereastră (roșu/galben/verde) acopereau începutul barei
  laterale: fereastra Reguli folosea `.hiddenTitleBar`, deci conținutul urca
  sub bara de titlu. Acum bară de titlu standard, unificată cu toolbar-ul.

### Added
- Subsolul barei laterale: buton „Setări…” și versiunea aplicației
  (Regula 7). „Setări…” și în meniul din bara de sus. Pe macOS 14+ prin
  `openSettings`, pe 13 prin `showSettingsWindow:`, cu activarea aplicației
  (altfel fereastra se deschidea în spate).
- Setări → General: selectorul de limbă în propria secțiune, prima.
- `scripts/release_engine.sh`: build complet → notarizare (`gdc-notary`) →
  staple → Gatekeeper → arhivă de client cu 3 fișiere → verificarea arhivei.
- Prima arhivă publică a build-ului complet (aplicație + extensie de rețea),
  notarizată. Până acum pe site era doar build-ul de interfață 2.0.1.

## v2.3.0 (2026-09-18) — Fereastra Reguli nouă, blocklist pe niveluri, import/export din fișier

### Added
- **Fereastra Reguli**: `NavigationSplitView` cu bară laterală pliabilă —
  Reguli (Toate, Active, Blocate, Schimbări recente, Temporare, Neaprobate
  cu badge), Grupuri (iCloud, macOS, Aplicații Apple, Terțe — cu comutator
  și meniu contextual: Editează, Exportă, Activează/Dezactivează, Șterge),
  Sugestii (Expirate), Mentenanță (Redundante, Identitate schimbată, Fără
  verificare de identitate, Executabil lipsă), Blocklist-uri.
- **Tabel** sortabil cu pictograma nativă a aplicației (NSWorkspace), proces,
  stare, destinație, dată; căutare după proces/cale/destinație.
- **Meniu contextual**: Regulă nouă pentru „…”, Duplică, Editează,
  Transformă în regulă globală, Activează/Dezactivează, Aprobă, Copiază
  regula/calea/domeniile, Arată în Finder, Repară calea procesului, Arată
  doar regulile pentru „…”, Exportă, Șterge.
- **Inspector** (`.inspector` pe macOS 14+, panou echivalent pe 13): antet
  cu pictogramă și fraza regulii, avertisment pentru executabil lipsă,
  cale, identitate (ID cod, Team ID, semnatar, verificarea semnăturii de pe
  disc), metadate (proprietar, creare, expirare), originea regulii, acțiuni.
- **Editor de reguli** (nouă/editare) cu validare: cale, regex, CIDR, port.
- **Blocklist StevenBlack pe niveluri**: Unified + Știri false, Jocuri de
  noroc, Pornografie, Rețele sociale + liste personalizate („Adaugă
  blocklist…”), îmbinate în flux într-un singur fișier, fără duplicate și
  fără excepțiile utilizatorului; „Verifică un domeniu”; meniu Blocklist în
  bara de sus.
- **Import din fișier** (NSOpenPanel .json/.lsrules/.plist/.xbel), formatul
  recunoscut după conținut: export Little Snitch, exportul JSON LuLu,
  `rules.plist` LuLu. Ghid pas cu pas pentru exportul manual.
- **Export** în format `.lsrules` (reimportabil în GDC sau Little Snitch).

### Changed
- **Blocklist-ul e aplicat acum de motor** (`useBlockList`/`blockList`),
  pentru FIECARE conexiune. Înainte GDC îl verifica doar la conexiunile care
  ajungeau la o alertă, deci aplicațiile deja permise îl ocoleau complet.
- Nivelurile vechi Minim/Mediu/Maxim migrate exact („Mediu” descărca de fapt
  lista fakenews, nu reclame, cum scria).
- Comutarea Permis/Blocat modifică regula existentă (înainte adăuga una nouă
  pe tot procesul, lângă cea veche).
- Ferestrele nu mai au dimensiuni fixe (alertă, setări, Despre, configurare).

### Not available (motorul LuLu nu are datele)
- Prioritate, contor de utilizare, ultimul acces, cale „via”, checksum,
  sugestiile Login/Full Screen, „Remove from Local Rule Group”.

## v2.2.1 (2026-09-18) — Log de diagnostic local (Regulile 25, 39)

### Added
- `DiagnosticLog`: fiecare eveniment ajunge în unified log (subsistemul
  `dev.gordas.GDCFirewall`) ȘI în `~/Library/Logs/GDCFirewall.log`, o linie
  per eveniment (`timestamp NIVEL [categorie] mesaj`), rotire la 5 MB.
  Nivelul debug intră în fișier doar cu
  `defaults write dev.gordas.GDCFirewall GDCFirewall.verboseLog -bool true`.
- Se loghează: pornirea (versiuni, macOS, limbă), stările extensiei și ale
  filtrului, înlocuirea extensiei, conexiunea XPC și reconectările, fiecare
  alertă (proces, destinație, risc) și fiecare verdict (permis/blocat,
  origine), regulile încărcate/schimbate/șterse, importurile, blocklist-ul,
  actualizarea automată, mutarea în Aplicații.
- `scripts/logs.sh` — procese, extensie, fișierul de log și motorul de
  filtrare într-un singur loc; `--follow` pentru urmărire live.

### Fixed
- **Aplicația cădea la fiecare pornire din v2.1.0** (SIGABRT, NSException în
  `NSWindow.init`): fereastra de configurare inițială se crea de pe un fir
  de fundal — `Task {}` pornit dintr-un context fără actor continua după
  `await` în afara firului principal. `AuxWindowPresenter` și
  `FirstRunSetup` sunt acum `@MainActor`, deci compilatorul refuză un astfel
  de apel. Găsit cu logul de diagnostic nou + raportul de crash.
- Verificarea automată de actualizări de la pornire ignora tăcut eșecurile
  (Regula 35): acum apar în log ca avertisment.
- Dezinstalatorul șterge și fișierul de log.

### Verified
- Importul Little Snitch pe un export `export-model` REAL (2026-09-18, prin
  promptul de administrator): formatul (lista `rules` la rădăcină) e cel
  presupus. Rezultat: 41 importate, 9 existente, sărite 576 (aplicații
  absente), 68 „via”, 19 de intrare, 13 „întreabă”. Numărul de „absente” e
  mare — de verificat dacă Little Snitch notează unele căi altfel.

## v2.2.0 (2026-09-18) — Interfață RO/EN/ES, ghid PDF generat din Swift

### Added
- **Interfața în română, engleză și spaniolă** (214 texte): `Resources/en.lproj`
  și `es.lproj/GDC.strings`, cheia fiind textul românesc din cod (`L("…")`).
  Limba urmează macOS sau se alege din Setări → General → Limbă; se aplică
  imediat. Tabelul `GDC`, nu `Localizable`, ca să nu se ciocnească cu
  catalogul motorului. Explicațiile proceselor din alerte sunt și ele traduse.
- `scripts/check-l10n.sh`, rulat de ambele scripturi de build: pică la o
  traducere lipsă, la specificatori `%@`/`%d` diferiți (crash la formatare),
  la text de interfață neîmpachetat în `L()` și la chei dinamice nevăzute.
- **Ghidul PDF generat din Swift** (`installer/generate-guide.swift`),
  regenerat la fiecare `build_app.sh`: secțiuni noi pentru configurarea
  inițială, importul din LuLu și Little Snitch, mesajele din meniu, limbă.
  Se auto-verifică: secțiuni prezente, orientare, margini, cuvinte interzise.

### Changed
- Ghidul EN/ES folosește etichetele interfeței în limba lui (nu mai citează
  butoanele în română). Instalarea descrie arhiva `.zip` reală, nu un `.pkg`.
- `installer/generate_pdf.py` (reportlab) eliminat, înlocuit de generatorul Swift.

### Fixed
- Ghidul vechi scria „nu este un preț” / „not a price” / „no es un precio” —
  interzis de Regula 3. Reformulat; generatorul pică dacă reapare.

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
