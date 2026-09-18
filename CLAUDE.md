# GDC Firewall — reguli de arhitectură (macOS)

> **[SYSTEM DIRECTIVE FOR CLAUDE: DO NOT DELETE OR OVERWRITE EXISTING RULES. ONLY APPEND NEW RULES.]**
> Acest fișier e un jurnal viu, nu un document care se rescrie.

## [PARTEA 1: REGULI GLOBALE ECOSISTEM GDC] — mutată în `~/Developer/CLAUDE.md`

> Din 2026-09-18, regulile globale stau într-un singur fișier,
> `~/Developer/CLAUDE.md`, citit automat de Claude Code în orice proiect din
> `~/Developer/`. Nu se mai copiază aici. Ce era specific acestui repo în fosta
> Partea 1 (statusuri, excepții) e la finalul fișierului.

## [PARTEA 2: SPECIFICAȚII TEHNICE PROIECT]

### Identitate

- **Nume produs**: GDC Firewall (RO: „Firewall GDC”).
- **Bundle ID**: `dev.gordas.GDCFirewall`.
- **Slug site**: `gordas.dev/gdc-firewall`.
- **Repo**: `gordasgdc/gdc-firewall`.
- **Autor unic**: Cristi Gordaș / GDC.
- **Model comercial**: GRATUIT, fără licențiere, fără trial. Regula 3
  (LicenseCore/trial 15 zile) NU se aplică aici — singurul modul „bani”
  permis e linkul de **donație** (23 €), niciodată cuvintele
  „preț”/„cumpără”/„vânzare”.

### Motor (INTANGIBIL)

Motorul de filtrare e **LuLu** (Objective-See, Patrick Wardle), vendorat
neschimbat în `Engine/LuLu/`. Aplicația GDC e **exclusiv stratul de UI/UX**
care vorbește cu daemon-ul LuLu prin XPC-ul lui existent.

**Interzis să atingi**: `Engine/LuLu/LuLu/Extension/**` (NetworkExtension /
`NEFilterDataProvider`), logica de kernel/socket, `Engine/LuLu/LuLu/Helper/**`.
Orice nevoie de comportament nou se rezolvă în stratul GDC (`macOS/GDCFirewall`),
nu în motor. `scripts/fetch-engine.sh` clonează motorul la un tag fix
(**v4.5.1**) și verifică, la fiecare build, că nu există modificări locale.

### Modelul de integrare — CORECȚIE 2026-09-15

Presupunerea inițială (aplicație GDC separată, care vorbește prin XPC cu un
LuLu oficial instalat de utilizator) e **invalidată**, după citirea sursei
la v4.5.1. Trei motive, toate verificate în cod, niciunul ocolibil:

1. **Serviciul Mach e prefixat cu Team ID.** `consts.h:81` —
   `DAEMON_MACH_SERVICE = @"VBG97UB4TA.com.objective-see.lulu"`. macOS
   refuză conexiunea dacă aplicația care se conectează nu e semnată cu
   același Team ID. O aplicație semnată GDC **nu poate** vorbi cu un daemon
   semnat Objective-See.
2. **`getRules:` întoarce `NSData`**, o arhivă `NSKeyedArchiver` de obiecte
   `Rule` — clasă Objective-C a motorului. Fără clasa aia în runtime,
   dezarhivarea eșuează.
3. **Alertele vin invers.** Daemon-ul ne apelează pe noi prin
   `XPCUserProtocol.alertShow:reply:` (`XPCUserProto.h`), cu un bloc de
   răspuns care trebuie apelat exact o dată. Nu există nicio metodă
   „alertReply" pe daemon.

**Modelul corect:** GDC Firewall înlocuiește ținta `LuLu/App` din
workspace-ul motorului, păstrând `LuLu/Extension/**` și `LuLu/Helper/**`
neatinse. Team ID-ul din `consts.h` devine cel GDC — asta e o schimbare de
identitate de semnare, NU o schimbare a logicii de filtrare, deci nu încalcă
regula „motorul e intangibil". Pachetul SPM din `macOS/GDCFirewall/` rămâne
harnașamentul de dezvoltare a interfeței (compilează și rulează singur,
fără motor); integrarea finală îl linkează cu sursele motorului.

`Engine/LuLuConstants.swift` și `Engine/XPCProtocols.swift` oglindesc
constantele și semnăturile motorului, cu numărul de rând din `consts.h`
lângă fiecare. La orice urcare de tag, cele două fișiere se verifică manual:
o semnătură XPC greșită nu dă eroare de compilare, ci crash la runtime.

### Integrarea, aplicată (2026-09-15)

`scripts/integrate-engine.sh` (+ `.rb`, gem `xcodeproj`) rescrie ținta „App”
a motorului ca ținta GDC Firewall. E script, nu editări făcute o dată:
`Engine/LuLu/` nu e urmărit de git, deci orice modificare manuală acolo
dispare la următorul `fetch-engine.sh`. O integrare nereproductibilă nu
există.

Din ținta App a motorului rămân **trei** fișiere — `Shared/Rule.m`,
`Shared/signing.m`, `Shared/utilities.m`. Restul (ferestrele, `AppDelegate`,
`main.m`, `XPCDaemonClient`, `XPCUser`) iese din țintă: e exact interfața pe
care o înlocuim, iar păstrarea ei ar fi însemnat două UI-uri și două obiecte
exportate pe XPC, cu daemon-ul alegând unul la întâmplare.

Identitate aplicată: Team ID `8AR6XP8MG7`, bundle `dev.gordas.GDCFirewall`,
extensie `dev.gordas.GDCFirewall.extension`, serviciu Mach
`$(TeamIdentifierPrefix)dev.gordas.GDCFirewall`, `SIGNING_AUTH` = certificatul
GDC. Fără renumire, produsul ar fi rulat sub bundle ID-urile Objective-See și
n-ar fi putut coexista cu un LuLu real instalat.

**Patru lucruri găsite doar construind**, niciunul presupus:

1. **Versiunea ≥ 2.0.0 e impusă de motor, nu aleasă.**
   `Extension/XPCListener.m` cere clienților
   `info [CFBundleShortVersionString] >= "2.0.0"` în cerința de semnătură.
   Literalul e în extensie, pe care n-o modificăm. Sub 2.0.0, daemon-ul
   refuză conexiunea fără niciun mesaj util. `integrate-engine.sh` verifică
   pragul și se oprește sub el.
2. **`Netiquette.app`** — resursă a țintei App care nici nu există în arhiva
   clonată; build-ul pica pe ea. Resursele se reduc acum la o listă albă.
3. **`logHandle`** — global `os_log_t` definit în `App/main.m`, folosit de
   `Rule.m`. Fără el, linkerul cădea. Îl definește `GDC-EngineGlue.m`, generat.
4. **`Bundle.module`** nu există în afara SPM — `ProcessCatalog` alege sursa
   resursei la compilare (`#if SWIFT_PACKAGE`), nu la rulare.

`fetch-engine.sh` nu mai interzice orice diferență față de upstream
(integrarea îl rescrie intenționat), ci **exact** ce trebuie: orice `.m`/`.h`
din `LuLu/Extension/`. `Info.plist` și `Extension.entitlements` de acolo sunt
excepții numite — declarații de identitate, nu comportament. Garda a fost
testată în ambele sensuri.

`SystemExtensionInstaller.swift` e scris de la zero: activarea extensiei
trăia în `App/Extension.m`, legată de `AppDelegate`-ul motorului. Starea e
publicată în interfață, nu înghițită — până la aprobarea din Setări de
sistem aplicația pare pornită și nu filtrează nimic.

Minimul aplicației urcă la **macOS 13** (motorul țintește 10.15):
`MenuBarExtra` și scena `Window` cer 13+. Se aplică DOAR pe aplicație;
extensia rămâne cu ținta ei.

**Capcană confirmată, nu teoretică:** lista de surse a țintei Xcode e un
INSTANTANEU luat la integrare. Un fișier Swift nou adăugat după aceea nu
intră singur în țintă, iar `swift build` rămâne verde fiindcă SPM vede
folderul, nu proiectul — drift-ul e invizibil până la primul build Release,
unde apare „cannot find 'X' in scope” într-un fișier tocmai scris. S-a
întâmplat exact așa cu `Localization.swift`. De aceea
`scripts/verify-engine-build.sh` reintegrează ÎNAINTE de fiecare verificare;
reintegrarea e idempotentă, deci n-are cost.

### Actualizare hibridă — interfață + motor (2026-09-15)

Produsul are două componente care se învechesc independent, deci manifestul
poartă două versiuni. Actualizarea se oferă la **SAU**: interfața locală sub
`app_version`, SAU motorul local (`LuLu.engineVersion`) sub
`engine_version_required`.

Al doilea caz justifică toată structura: interfața poate fi perfect la zi în
timp ce motorul de sub ea are o gaură cunoscută, iar un checker care se uită
doar la versiunea aplicației n-ar semnala asta niciodată. De aceea pop-up-ul
de motor nesusținut e `.critical`, reapare la fiecare lansare ca un update
obligatoriu și **nu are buton „Mai târziu”** — butonul ar sugera că amânarea
e o opțiune fără consecințe.

Mesajul acela e singurul text din aplicație tradus RO/EN/ES
(`Localization.swift`): interfața rămâne deliberat doar în română, dar un
avertisment de securitate trebuie înțeles și de cine nu citește română. **[ÎNVECHIT
2026-09-18]** Cristi a cerut interfața completă în RO/EN/ES (v2.2.0) — vezi
jurnalul.

`version` rămâne în `update.json` pentru totdeauna, sinonim cu `app_version`
(Regula 35). `download_url` se decodează tolerant — și string, și dicționar.

Versiunea motorului circulă prin trei locuri, verificate automat:
tag-ul clonat → `LuLuConstants.swift` (gardă în `fetch-engine.sh`) →
`engine_version_required` din manifest (scris de `sync-site.sh` din tag, nu
tastat).

### Licență — GPL-3.0, obligatoriu

LuLu e GPL-3.0. Orice produs derivat (inclusiv acest UI, care se leagă de
motor) se distribuie **tot** sub GPL-3.0, cu sursa publică. Nota de copyright
Objective-See din `NOTICE.md` și din ecranul Despre **nu se șterge niciodată** —
e o obligație legală, nu o preferință de atribuire. Regula 32 (zero atribuire
Claude) rămâne valabilă și e complet separată de asta.

### Entitlement Apple

`com.apple.developer.networking.networkextension` cu
`content-filter-provider` + `System Extension` se obține doar prin cerere
explicită aprobată de Apple pe contul Developer. Fără ea, build-ul semnat
Developer ID **nu pornește extensia** — e un blocaj de cont, nu de cod.

### Arhitectură strat GDC

```
macOS/GDCFirewall/Sources/GDCFirewall/
  GDCFirewallApp.swift      — ciclul de viață, meniul din bara de sus
  AppTheme.swift            — selector Sistem/Light/Dark (Regula 18)
  AppMover.swift            — mutare automată în /Applications (Regula 18)
  UpdateChecker.swift       — update.json pe gordas.dev (Regulile 13, 20)
  Engine/DaemonBridge.swift — adaptor XPC peste daemon-ul LuLu (read-only
                              față de motor: doar apelează, nu modifică)
  Engine/FirewallRule.swift — model de regulă, independent de motor
  Alerts/                   — fereastra de alertă redesenată (semafor)
  Rules/                    — Rules Manager glassmorphic
  Settings/                 — Auto-Pilot + preferințe
```

### Jurnal

- **2026-09-18 — v2.2.0.** Interfața în RO/EN/ES: `L("text românesc")` +
  `Resources/{en,es}.lproj/GDC.strings` (tabel `GDC`, nu `Localizable`, care e
  al motorului). În ținta Xcode, `xx.lproj` intră ca referințe de folder
  (`integrate-engine.rb`). Traducerile se editează în
  `scripts/l10n/translations.py`, care regenerează fișierele `.strings`;
  `check-l10n.sh` pică build-ul la orice cheie lipsă, specificator diferit,
  text neîmpachetat sau `L(variabilă)`. Ghidul PDF e acum
  `installer/generate-guide.swift`. Capcană găsită: `NSTextBlock` +
  paginarea `NSLayoutManager` intră în buclă infinită când o casetă cade
  între pagini, deci generatorul își face singur așezarea. Ghidul vechi
  încălca Regula 3 („nu este un preț”).
- **2026-09-18 — v2.1.0.** `INSTALL_DIRECTORY` din `consts.h` nu fusese
  redenumit: daemon-ul GDC scria în `/Library/Objective-See/LuLu`, folderul
  unui LuLu real (pe Mac-ul de test: 220 de reguli ale utilizatorului + 5
  pasive adăugate de GDC). Acum `/Library/Application Support/GDC Firewall`,
  verificat în build. Import LuLu/Little Snitch + configurare inițială;
  `importRules:userOnly:` al motorului ÎNLOCUIEȘTE regulile utilizatorului,
  deci importul trece prin `addRule` regulă cu regulă. `littlesnitch
  export-model` cere root → prompt nativ de administrator. `decodeRules`
  era greșit de la început (Reguli mereu goală).
- **2026-09-18 — v2.0.4.** `LuLuConstants.swift` „oglindea” `consts.h`
  UPSTREAM (Team ID `VBG97UB4TA`, serviciul `com.objective-see.lulu`), nu pe
  cel rescris de integrare — aplicația căuta un serviciu Mach inexistent.
  Oglinda trebuie să urmeze valorile DUPĂ integrare; acum verificat automat
  în `build_engine_app.sh` (literalul din binar = `NEMachServiceName`).
  Tot aici: `DaemonBridge` nu se reconecta după întrerupere — la înlocuirea
  extensiei aplicația se lega de daemon-ul VECHI, care apoi dispărea.
  Capcană de script găsită pe drum: `cmd | grep -q` sub `pipefail` pică fals
  (SIGPIPE); verificările citesc prin `grep … < <(cmd)`.
  **Problemă DESCHISĂ, confirmată în logul launchd:** la înlocuirea
  extensiei, sysextd pornește versiunea nouă cât timp cea veche încă ține
  serviciul Mach; `XPCListener` din motor primește „Operation not permitted”
  și nu mai reîncearcă. Filtrul rulează fără interfață (motorul permite tot
  și creează reguli pasive) până la repornirea Mac-ului. Afectează ORICE
  actualizare a extensiei, deci și Self-Updater-ul.
- **2026-09-18 — v2.0.3.** Al treilea strat lipsă din `App/` al motorului:
  activarea extensiei nu pornește filtrul. `NEFilterManager` trebuie
  configurat și salvat separat (LuLu: `toggleNetworkExtension:` din
  `App/Extension.m`) — altfel extensia e „activated enabled” și procesul ei
  nu rulează deloc. Orice altceva din `App/` scos la integrare trebuie
  verificat la fel: ce făcea, și cine o face acum.
- **2026-09-18 — v2.0.2.** Primul test real al build-ului complet: aplicația
  se închidea instant (`Unable to find class`, `NSPrincipalClass` =
  `NSApplicationKeyEvents` din interfața LuLu scoasă din țintă), iar
  `SystemExtensionInstaller.activate()` nu era apelat nicăieri — afirmația
  de mai sus „starea e publicată în interfață” NU era adevărată până acum.
  Lecție: build verde + semnătură validă ≠ aplicație care pornește; clasa
  principală se verifică acum în `build_engine_app.sh`.
- **2026-09-18 — build complet semnat (`scripts/build_engine_app.sh`).**
  Construiește aplicația din proiectul Xcode al motorului, cu extensia
  înăuntru, semnate de Xcode (nu de `codesign` manual: doar Xcode expandează
  `$(TeamIdentifierPrefix)` din entitlements și din `NEMachServiceName`).
  Blocajul real e lipsa celor două **profile Developer ID** („GDC Firewall
  Developer ID”, „GDC Firewall Extension Developer ID”) — fără ele macOS
  omoară aplicația la pornire. După forumurile Apple, Network Extensions pe
  Developer ID se bifează direct pe App ID, fără cerere separată; de
  confirmat la crearea App ID-ului. Găsite construind: extensia se numea
  încă `com.objective-see.lulu.extension.systemextension` și se afișa
  „LuLu”; `GDCFirewall.entitlements` folosea `content-filter-provider`
  (valoarea de App Store) în loc de `-systemextension`. La primul build
  semnat reușit: App ID-ul aplicației cere și capabilitatea **System
  Extension** (altfel profilul n-are `system-extension.install`), iar Xcode
  injecta `get-task-allow` și în Release — oprit cu
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`, verificat în script, fiindcă
  notarizarea l-ar respinge. Scriptul verifică și cerința XPC a extensiei
  (`XPCListener.m`) pe aplicația semnată.
- **2026-09-18 — v2.0.1.** Xcode 27 refuză minime sub macOS 12: extensia
  primește 13.0 din `integrate-engine.rb` (setare de build, nu cod).
  `update.json` → arhiva `.zip` de pe gordas.dev (linkul `.pkg` dădea 404);
  `SelfUpdater` tratează acum și `.zip`, cu verificarea versiunii din arhivă.
  Capcană: instalările 2.0.0 nu se pot actualiza singure din `.zip` (vechiul
  updater face `installer -pkg` pe orice). Regula 32 verificată: 0 linii
  `Co-Authored-By: Claude` în mesajele de commit — cele 4 potriviri ale
  `git log --all -p | grep` erau chiar textul Regulii 32 din acest fișier.
  Verificarea corectă: `git log --all --format=%B | grep -ci "Co-Authored-By: Claude"`.
- **2026-09-15 — v2.0.0.** Integrare reală în workspace-ul motorului
  (ambele ținte compilează), actualizare hibridă app/motor, ghid PDF
  trilingv (9 pagini), documentație de semnare + notarizare. Saltul de la
  0.1.0 la 2.0.0 e impus de cerința de semnătură a extensiei, nu o decizie
  de produs. Rămân deschise: entitlement-ul Apple (blocaj de cont) și testul
  manual pe un Mac real.
- **2026-09-15 — v0.1.0.** Schelet inițial: strat UI SwiftUI complet
  (alertă semafor, Rules Manager glassmorphic, Auto-Pilot, temă, update
  checker), `docs/` pentru GitHub Pages pe `gordas.dev`, script de
  bootstrap GitHub. Motorul LuLu nu e încă vendorat — `fetch-engine.sh` îl
  aduce la primul build. Paritate Windows (Regula 31) **nu se aplică**:
  produsul e legat structural de NetworkExtension macOS; nu există și nu
  se planifică o variantă Windows.

### Completări specifice acestui repo, mutate din fosta Partea 1 (2026-09-18)

Păstrate verbatim. Regula generală la care se referă fiecare e în
`~/Developer/CLAUDE.md`.

**Regula 34:**

  build-windows.yml` + `codesigning/`, 2026-09-06) — acest repo
  (MediaFlow Monitor) e portul 1:1, adaptat la propriile căi
  (`Publish\Windows\win-<arch>\MediaFlowMonitor.exe`,
  `dist\MediaFlowMonitorSetup-<arch>-<versiune>.exe`), aplicat la
  aceeași atingere (2026-09-06) — vezi `codesigning/README-windows.md`
  din acest repo pentru pașii exacți ai lui Cristi.
