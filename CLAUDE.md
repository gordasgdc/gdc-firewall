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
  Rules/                    — Rules Manager glassmorphic [ÎNVECHIT 2026-09-18:
                              bară laterală + tabel + inspector, vezi v2.3.0]
  Blocklist/                — surse StevenBlack pe niveluri → fișier aplicat de motor
  Import/                   — configurare inițială, import (LuLu, Little Snitch,
                              fișier) și export .lsrules
  Settings/                 — Auto-Pilot + preferințe
```

### Reguli permanente descoperite la 2.3.x (2026-09-19)

Regulile generale sunt în `~/Developer/CLAUDE.md` (40 — App Translocation,
41 — link de descărcare versionat, 42 — SIP). Aici, aplicarea lor în repo:

1. **App Translocation** → `AppMover.swift`: copia din `/Applications`
   primește `com.apple.quarantine` fără bitul 0x0080 (carantina rămâne);
   instalare deja izolată = reparare pe loc; niciodată copiere peste sine.
   Testul se face cu arhiva notarizată + carantină `0083` + Archive Utility.
2. **Arhiva versionată** → `scripts/sync-site.sh` rescrie butonul din
   `docs/index.html` și `download_url` din `update.json` la
   `GDCFirewall-macOS-<versiune>.zip` și pică dacă arhiva lipsește; copia
   `GDCFirewall-macOS.zip` rămâne. Verificare live: `scripts/verify-download.sh <versiune>`.
3. **Dezactivarea extensiei de rețea cu SIP activ** → singura cale e
   aplicația care o conține: `GDC Firewall --uninstall-extension`
   (`UninstallMode.swift`: scoate configurația `NEFilterManager`, apoi
   `OSSystemExtensionRequest.deactivationRequest`; ieșire 0/2/1).
   `Dezinstalare_GDCFirewall.command` găsește copiile după bundle ID, pune o
   copie 2.3.3+ în `/Applications` dacă e nevoie și o apelează;
   `systemextensionsctl uninstall` e doar rezervă, cu `csrutil status` =
   dezactivat. Presupunere NEVERIFICATĂ: că dezactivarea, ca și activarea,
   cere aplicația în `/Applications` — de aceea copia e pusă acolo.
4. **SIP — ce e validat doar pe Mac-ul de dezvoltare (SIP dezactivat)** și
   trebuie confirmat pe un Mac cu SIP activ:
   - înlocuirea secvențială: `launchctl bootout system/NetworkExtension.…`
     pe jobul vechi (aplicație + scriptul SelfUpdater). Dacă SIP îl
     blochează, aplicația intră în „Actualizarea motorului e amânată” și
     rămâne pe extensia veche (funcțională, același motor) — de remediat
     atunci: la un eșec care NU e anularea utilizatorului, înlocuire directă
     + mesajul de repornire, în loc de amânare;
   - dezinstalatorul GDC (calea prin aplicație) și curățarea Little Snitch /
     LuLu (calea prin Finder, care declanșează dezinstalarea extensiilor).
   **[ÎNVECHIT 2026-09-25]** Presupunerea „Mac-ul de dezvoltare are SIP
   dezactivat” nu mai e valabilă: SIP e ACTIVAT permanent pe Mac-ul lui Cristi,
   ca la clienți. Rezultat verificat la primul test cu SIP activ (2.3.4 → 2.3.5):
   `launchctl bootout` pe jobul extensiei → „Operation not permitted”, deci
   înlocuirea secvențială NU funcționează la niciun client. Remedierea
   prevăzută mai sus e aplicată în 2.3.5 (punctul 5).
5. **Totul se construiește, se testează și se actualizează cu SIP ACTIV
   (2026-09-25).** Fără `launchctl bootout`/`kickstart` pe joburile extensiei,
   fără `systemextensionsctl` ca pas normal. Actualizarea extensiei = DOAR
   `OSSystemExtensionRequest.activationRequest` + `.replace` (ca LuLu
   upstream); garda de actualizare pusă înainte; dacă extensia nouă pornește
   fără serviciul Mach (cursa), mesaj de repornire. Dezactivarea
   (`--uninstall-extension`) cere o nouă aprobare la reactivare — nu e cale de
   actualizare. Un test „trecut” fără `csrutil status` = enabled nu
   dovedește nimic.

### Jurnal

- **2026-09-25 — v2.3.5 (nepublicată).** UpdateGuard: `release()` ștergea copia salvată și cu motorul neconectat, iar
  `engage()` următor salva starea gărzii ca „anterioară” → blocare permanentă a oricărui binar fără regulă (-1005).
  Acum ridicarea se confirmă din răspunsul `updatePreferences`, starea gărzii nu se salvează/reface niciodată,
  autoreparare la conectare; garda se ridică doar când rulează exclusiv extensia din pachet. Primul test cu SIP
  activ: `bootout` interzis → înlocuirea secvențială scoasă, înlocuire doar prin API-ul oficial + repornire la
  cursă. Teste: `Tests/GDCFirewallTests`; integrare: `scripts/verify-update-guard.sh`. Capcane găsite:
  `translations.py` scria într-o cale fixă (checkout-ul principal) — acum relativ la repo; testele scriau în
  logul real — acum fișier temporar sub XCTest.
- **2026-09-20 — v2.3.4 verificată LIVE** (`verify-download.sh 2.3.4`: 11 ✓, 0 ✗; DMG + `GDCFirewall-macOS.dmg` stabil
  publicate). Regula globală 45 (DMG/PKG notarizat, fără `.command`/zip) e în `~/Developer/CLAUDE.md` și
  `~/Developer/ARCHITECTURE_PATTERNS.md` (K).
- **2026-09-20 — v2.3.4. Distribuție DMG notarizat.** Chrome bloca
  `GDCFirewall-macOS-2.3.3.zip` ca „suspectă”; arhiva a fost înlocuită cu
  `GDCFirewall-macOS-<v>.dmg` (semnat Developer ID, notarizat, stapled,
  verificat cu spctl după montare; `release_engine.sh`). Butonul paginii și
  `download_url.mac_dmg` → DMG. `download_url.mac` RĂMÂNE `.zip` versionat:
  Self-Updater-ul ≤2.3.3 nu instalează `.dmg` (ar rula `installer -pkg`);
  `sync-site.sh` face zip-ul din aplicația din DMG (doar canal updater).
  Self-Updater 2.3.4 știe DMG/zip/pkg. Nou: ghid de aprobare a extensiei
  (dialog o dată + „Deschide Setări de sistem…” →
  `Privacy_Security`). Regula 6 („exact 3 fișiere în zip”) nu mai se aplică
  distribuției: DMG = aplicație + link Aplicații + ghid PDF; dezinstalarea
  = `GDC Firewall --uninstall-extension`. Nu s-a testat pe un Mac curat.

- **2026-09-19 — instrumente, fără versiune nouă de aplicație.**
  `scripts/Dezinstalare_LittleSnitch_LuLu.command` e acum sursa unică a
  curățării Little Snitch + LuLu (dublu-clicabilă, se auto-elevează cu
  `sudo`, pauză la final); `cleanup_competing_firewalls.sh` doar o apelează.
  `--dry-run --assume-sip-on` arată planul pentru SIP activ (Regula 42):
  extensiile se scot prin Finder (aplicația la Coș), nu prin
  `systemextensionsctl`. Instrucțiuni pentru prieteni/clienți:
  `scripts/Dezinstalare_LittleSnitch_LuLu.md` — metoda principală e
  `bash <fișier>` în Terminal, fiindcă un `.command` descărcat e blocat de
  Gatekeeper la dublu-click, iar `bash` citește scriptul ca text. Pachet de
  trimis: `dist/Dezinstalare_LittleSnitch_LuLu-1.0.0.zip` (local, `dist/` e
  ignorat de git).
- **2026-09-19 — v2.3.3.** App Translocation, verificat EMPIRIC pe macOS 26
  (arhivă cu carantină `0083;…;Safari`, dezarhivată cu Archive Utility):
  izolarea depinde DOAR de bitul 0x0080 din `com.apple.quarantine` — `0083`,
  `00c3`, `0081` → izolată; `0003`, `0043`, `0001` → rulează pe loc. Bitul
  supraviețuiește copierii cu FileManager ȘI mutării prin Finder/AppleScript
  (Finder nu schimbă atributul). Bug real în 2.3.2 publicat: copia din
  /Applications pornea izolată → AppMover cerea mutarea din nou → a doua
  mutare copia aplicația peste ea însăși și o ducea la Coș (reprodus: aplicația
  a dispărut din /Applications). Reparat: copia instalată primește atributul
  FĂRĂ bitul 0x0080 — carantina rămâne (nu e „hack-ul xattr” interzis de
  Regula 6, care scotea carantina ca să ocolească Gatekeeper; aici aplicația a
  trecut deja de Gatekeeper, iar copia e verificată). Comparația cu
  destinația se face pe identitatea fișierului, nu pe text. Aplicația e
  LSUIElement: fără `setActivationPolicy(.regular)` promptul de la pornire
  putea rămâne ascuns (cauza probabilă a „nu se declanșa”). Capcană de mediu:
  `open -b` pornește ce găsește LaunchServices — pe Mac-ul de dezvoltare,
  build-ul din `Build/engine/Release`, nu cel din /Applications; testele
  pornesc după cale. Dezinstalare: fără SIP dezactivat, extensia o poate
  dezactiva doar aplicația care o conține → `GDC Firewall --uninstall-extension`
  (`UninstallMode.swift`), apelat de `Dezinstalare_GDCFirewall.command`, care
  găsește copiile după bundle ID (mdfind + locuri uzuale), pune o copie
  2.3.3+ în /Applications dacă trebuie, iar fără nicio copie folosește
  `systemextensionsctl` (doar cu SIP dezactivat). Arhiva de pe site e
  versionată (`sync-site.sh` rescrie butonul și `update.json`; copia stabilă
  rămâne, Regula 17), verificat de `scripts/verify-download.sh`.
- **2026-09-18 — v2.3.2. Cursa de înlocuire a extensiei, REZOLVATĂ** (vezi
  problema deschisă din v2.0.4). Fapte verificate: oprirea filtrului nu
  oprește procesul extensiei (același PID); `uninstall` XPC șterge folderul
  de date (inutilizabil ca repornire); `launchctl print system/<eticheta>`
  arată fără root dacă serviciul deține endpoint-ul Mach (`active = 1`).
  Eticheta = `NetworkExtension.dev.gordas.GDCFirewall.extension.<short>.<build>`
  din Info.plist-ul extensiei. Reparația = `kickstart -k` pe serviciul nou
  (root): în SelfUpdater fără parolă în plus, manual cu un prompt. Garda:
  modul pasiv „block, fără reguli” e verificat în motor ÎNAINTEA
  `allowNoClient`, deci blochează necunoscutele în fereastra fără client.
  **[ÎNVECHIT în aceeași zi — `kickstart -k` NU repară]**, dovedit la primul
  test real (2.3.1 → 2.3.2): logul launchd arată că `nesessionmanager`
  trimite jobul nou cât timp cel vechi încă e în launchd („The endpoint …
  defined in plist already exists and is owned by …2.3.1”), iar launchd scoate
  endpoint-ul din DEFINIȚIA jobului nou. `kickstart -k` repornește procesul cu
  aceeași definiție → tot fără serviciu Mach. Rezultat: 15 prompturi de parolă
  în buclă (verificarea de sănătate reluată după fiecare eșec). Reparat:
  promptul automat apare o singură dată per versiune/lansare, iar un eșec nu
  mai trece prin `.idle`. Ipoteza nouă, de verificat cu
  `scripts/repair-engine.sh`: `bootout` pe jobul nou, ca macOS să-l retrimită
  cu endpoint-ul liber. Tot aici: `scripts/cleanup_competing_firewalls.sh`
  (Little Snitch + LuLu → Coș, GDC exclus și verificat la final).
  **[ÎNVECHIT și ipoteza `bootout` — rezolvarea FINALĂ e mai jos]**: `bootout`
  pe jobul nou îl scoate cu tot cu înregistrarea providerului
  (`nesessionmanager`: „Found 0 registrations”), iar comutarea filtrului nu-l
  retrimite — doar o activare/înlocuire sau repornirea Mac-ului înregistrează
  din nou. Test decisiv: FĂRĂ job vechi în launchd, înlocuirea se înregistrează
  curat. **Rezolvarea verificată = înlocuire secvențială**: jobul VECHI se
  scoate (`bootout`, root) ÎNAINTE de cererea de activare — manual o parolă
  (`activateSequentially`), în SelfUpdater în scriptul root, înainte de
  `open`. Test real 2.3.1 → 2.3.2: jobul nou deține serviciul Mach, checkIn
  acceptat, fără repornire. Capcană găsită la același test: prima citire
  `launchctl print` la 16 ms după activare arată încă „fără serviciu Mach”
  (ascultătorul pornește după) — verdictul se dă după 10 s de așteptare.
  `repair-engine.sh` (făcea `bootout` pe jobul nou) e șters, înlocuit de
  `engine-status.sh` (doar diagnostic). AppMover: doar `/Applications`
  (sysextd refuză altă locație), App Translocation rezolvată prin
  `SecTranslocateCreateOriginalPathForURL`, relansare după ieșirea
  procesului (un `open` cât rulează reactivează instanța veche), cale admin
  pentru o copie deținută de root.
- **2026-09-18 — v2.3.1.** Prima publicare a build-ului complet notarizat:
  `scripts/release_engine.sh` (profil Keychain `gdc-notary`, același ca
  DataMover). Arhiva de pe gordas.dev conține de acum aplicația CU extensia;
  `build_app.sh` (harnașamentul SPM, fără extensie) nu mai e calea de
  release. Suprapunerea butoanelor de fereastră peste bara laterală venea
  din `.hiddenTitleBar` pe scena Window — reparată la cauză, nu cu padding.
- **2026-09-18 — v2.3.0.** Fereastra Reguli în stil Little Snitch (bară
  laterală, tabel, inspector, meniu contextual). Descoperire majoră: GDC
  verifica blocklist-ul DOAR la alerte, deci nimic din ce era deja permis nu
  trecea prin el. Motorul LuLu are propriul blocklist (`useBlockList` +
  `blockList`, Extension/BlockOrAllowList.m) aplicat fiecărei conexiuni
  înaintea regulilor și reîncărcat la schimbarea fișierului — GDC scrie acum
  `~/Library/Application Support/GDCFirewall/blocklist.txt` și îl activează
  prin `updatePreferences` la fiecare conectare. Motorul verifică blocklist-ul
  ÎNAINTEA listei lui de excepții și face potrivire EXACTĂ pe nume, deci
  excepțiile se scot din fișier la îmbinare. `csInfo` NU are `teamID`:
  Team ID-ul se extrage din certificatul frunză. Câmpurile Little Snitch
  fără echivalent în motor (prioritate, utilizare, via, checksum) nu se
  afișează. `.inspector` cere macOS 14 — pe 13 un `HSplitView` echivalent.
- **2026-09-18 — v2.2.1.** Log de diagnostic local (Regula 39, nouă în
  `~/Developer/CLAUDE.md`, cu GDC Firewall ca implementare de referință):
  `DiagnosticLog.swift` → unified log + `~/Library/Logs/GDCFirewall.log`;
  `scripts/logs.sh [minute|--follow]`. Extensia (motorul, root) rămâne doar
  în unified log, sub `com.objective-see.lulu`; scriptul o include, filtrând
  zgomotul de sistem. Diagnoza aceleiași zile: 2.2.0 instalat dar nepornit,
  extensia activă era încă 2.0.4 — fără ascultător XPC (cursa de înlocuire)
  și scriind în folderul LuLu vechi. Primul test cu logul nou a arătat că
  2.1.0–2.2.1 cădeau la pornire: `FirstRunSetup` crea fereastra de pe un fir
  de fundal (`Task {}` neizolat + `await`). Acum `@MainActor`. Lecție: orice
  cod care atinge AppKit stă într-un tip `@MainActor`, nu doar „se apelează
  de obicei de pe main”.
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
  **Problemă DESCHISĂ [ÎNCHISĂ în v2.3.2], confirmată în logul launchd:** la înlocuirea
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

### Handoff — fișierul de stare (Regula 50, `~/Developer/CLAUDE.md`)

- Fișierul de stare al acestui proiect: `PROJECT_STATE.md` (rădăcina repo-ului). La orice sesiune nouă se citește
  ÎNTÂI el, apoi doar fragmentele strict necesare; se actualizează la milestone-uri și obligatoriu la final.
  Dacă lipsește, se creează la prima sesiune care atinge proiectul. Repo PUBLIC: fișierul e intern, listat în `.gitignore` (doar local, Regula 29).
- Restructurarea/ștergerea lui și orice modificare a acestui `CLAUDE.md`: doar cu diff-ul arătat și acordul lui Cristi.
