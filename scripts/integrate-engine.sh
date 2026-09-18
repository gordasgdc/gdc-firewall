#!/bin/bash
# Transformă workspace-ul motorului în workspace-ul GDC Firewall.
#
# De ce e script și nu o serie de editări făcute o dată: `Engine/LuLu/` NU e
# urmărit de git (îl aduce fetch-engine.sh). Orice modificare făcută manual
# acolo dispare la următoarea clonare. Integrarea trebuie să fie
# reproductibilă, altfel nu există.
#
# Ce se atinge: identitatea (Team ID, bundle ID, numele serviciului Mach) și
# ținta „App”, care e înlocuită integral de interfața GDC.
# Ce NU se atinge: `LuLu/Extension/**` — niciun fișier sursă, niciun rând de
# logică de filtrare. Două excepții, ambele declarații de identitate și
# ambele verificate de fetch-engine.sh: `Extension/Info.plist` (numele
# serviciului Mach trebuie să coincidă cu cel din consts.h) și
# `Extension/Extension.entitlements` (grupul de aplicații).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT/Engine/LuLu"
PROJECT="$ENGINE/LuLu/LuLu.xcodeproj"
SHARED="$ENGINE/LuLu/Shared"

TEAM_ID="8AR6XP8MG7"
SIGNING_AUTH="Developer ID Application: DUMITRU CRISTINEL GORDAS (${TEAM_ID})"
APP_ID="dev.gordas.GDCFirewall"
# Numele profilelor Developer ID din portalul Apple, exact cum sunt create
# acolo. Xcode le caută după nume; build_engine_app.sh le citește din proiect.
APP_PROFILE="GDC Firewall App Developer ID"
EXT_PROFILE="GDC Firewall Extension Developer ID"
MACH_SUFFIX="$APP_ID"

# Regula 0: versiunea vine din bundle-ul nostru, nu dintr-o constantă scrisă
# aici — două surse de adevăr ar diverge la primul bump.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/macOS/GDCFirewall/Resources/Info.plist")"

# `xcodeproj` e singura dependinta externa a integrarii. Editarea unui
# project.pbxproj cu sed e o reteta de proiect corupt tacut — gem-ul stie
# formatul, noi nu.
if ! ruby -e "require 'xcodeproj'" 2>/dev/null; then
  echo "‼️  Lipseste gem-ul 'xcodeproj'. Instaleaza-l o singura data:"
  echo "    gem install xcodeproj --user-install"
  exit 1
fi

bash "$ROOT/scripts/fetch-engine.sh"

# ---------------------------------------------------------------------------
# Verificarea care justifică versiunea >= 2.0.0.
#
# `Extension/XPCListener.m` impune clienților o cerință de semnătură care
# include `info [CFBundleShortVersionString] >= "2.0.0"`. Literalul ăla e în
# extensie, pe care n-o modificăm — deci aplicația TREBUIE să fie 2.0.0+, sau
# daemon-ul îi refuză conexiunea fără niciun mesaj util.
# ---------------------------------------------------------------------------
MAJOR="${VERSION%%.*}"
if [ "$MAJOR" -lt 2 ]; then
  echo "‼️  Versiunea aplicației e $VERSION, dar extensia acceptă doar clienți >= 2.0.0"
  echo "    (Engine/LuLu/LuLu/Extension/XPCListener.m, cerința de semnătură)."
  echo "    Ridică CFBundleShortVersionString la 2.0.0 sau mai mult."
  exit 1
fi

echo "→ Identitate în consts.h…"
python3 - "$SHARED/consts.h" "$TEAM_ID" "$SIGNING_AUTH" "$APP_ID" "$MACH_SUFFIX" <<'PY'
import pathlib, re, sys
path, team, auth, app_id, mach = sys.argv[1:6]
p = pathlib.Path(path)
s = p.read_text()

def define(text, name, value):
    pattern = rf'(#define\s+{re.escape(name)}\s+@?")[^"]*(")'
    new, n = re.subn(pattern, lambda m: m.group(1) + value + m.group(2), text)
    if n != 1:
        sys.exit(f"consts.h: am gasit {n} definitii pentru {name}, asteptam exact 1")
    return new

s = define(s, "DAEMON_MACH_SERVICE", f"{team}.{mach}")
s = define(s, "SIGNING_AUTH", auth)
s = define(s, "APP_ID", app_id)
s = define(s, "EXT_BUNDLE_ID", f"{app_id}.extension")
p.write_text(s)
print("   DAEMON_MACH_SERVICE, SIGNING_AUTH, APP_ID, EXT_BUNDLE_ID")
PY

echo "→ Numele serviciului Mach în Extension/Info.plist…"
/usr/libexec/PlistBuddy -c "Set :NetworkExtension:NEMachServiceName \$(TeamIdentifierPrefix)${MACH_SUFFIX}" \
  "$ENGINE/LuLu/Extension/Info.plist"
# Numele afișat în Setări de sistem, la aprobarea și în lista extensiilor.
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName GDC Firewall" \
  "$ENGINE/LuLu/Extension/Info.plist"

echo "→ Grupul de aplicații în entitlements…"
for f in "$ENGINE/LuLu/App/App.entitlements" "$ENGINE/LuLu/Extension/Extension.entitlements"; do
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 \$(TeamIdentifierPrefix)${MACH_SUFFIX}" "$f"
done

echo "→ Info.plist-ul aplicației…"
APP_PLIST="$ENGINE/LuLu/App/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$APP_PLIST" >/dev/null 2>&1 || true; }
pb "Set :CFBundleName GDC Firewall"
pb "Set :CFBundleDisplayName GDC Firewall"
pb "Delete :NSMainNibFile"          # punctul de intrare e @main-ul SwiftUI, nu un xib
pb "Add :LSUIElement bool true"     # aplicația trăiește în bara de meniu
pb "Set :LSUIElement true"
pb "Set :NSHumanReadableCopyright © 2026 Cristi Gordaș / GDC. GPL-3.0. Motor: LuLu © Objective-See."
pb "Set :NSSystemExtensionUsageDescription GDC Firewall are nevoie de o extensie de sistem pentru a putea filtra conexiunile de rețea."

echo "→ Antetul de punte Obj-C → Swift…"
BRIDGE="$ENGINE/LuLu/GDC-Bridging-Header.h"
{
  echo "// Generat de scripts/integrate-engine.sh — nu edita aici, se pierde."
  echo "//"
  echo "// Expune Swift-ului STRICT clasa \`Rule\`. Protocoalele XPC NU se importă:"
  echo "// stratul GDC le redeclară în Swift (Engine/XPCProtocols.swift), iar un"
  echo "// import ar duce la două declarații ale aceluiași protocol."
  echo '#import "Rule.h"'
} > "$BRIDGE"

echo "→ Definiția globalilor rămași fără gazdă…"
# `Rule.m` scrie în `logHandle`, un `os_log_t` global pe care îl definea
# `App/main.m` — fișier pe care l-am scos din țintă odată cu interfața
# veche. Fără el, linkerul cade cu „Undefined symbols: _logHandle”.
# Îl definim noi, o dată, cu subsistemul GDC.
GLUE="$ENGINE/LuLu/GDC-EngineGlue.m"
{
  echo "// Generat de scripts/integrate-engine.sh — nu edita aici, se pierde."
  echo "#import <Foundation/Foundation.h>"
  echo "@import OSLog;"
  echo ""
  echo "// Definit altfel in App/main.m, care nu mai face parte din tinta."
  echo "os_log_t logHandle = nil;"
  echo ""
  echo "__attribute__((constructor)) static void gdcInitLogHandle(void) {"
  echo "    logHandle = os_log_create(\"dev.gordas.GDCFirewall\", \"engine\");"
  echo "}"
} > "$GLUE"

echo "→ Pictograma…"
ICON_DST="$ENGINE/LuLu/App/Assets.xcassets/AppIcon.appiconset"
rm -f "$ICON_DST"/*.png "$ICON_DST"/Contents.json
cp "$ROOT/macOS/GDCFirewall/Resources/Assets.xcassets/AppIcon.appiconset/"* "$ICON_DST/"

echo "→ Ținta App → GDC Firewall…"
ruby "$ROOT/scripts/integrate-engine.rb" \
  "$PROJECT" "../../../macOS/GDCFirewall/Sources/GDCFirewall" \
  "$TEAM_ID" "$APP_ID" "$VERSION" "$APP_PROFILE" "$EXT_PROFILE"

# Marcăm starea, ca fetch-engine.sh să știe că diferențele din motor sunt
# ale noastre, nu accidentale.
echo "$VERSION" > "$ENGINE/.gdc-integrated"

echo
echo "✓ Motor integrat (aplicație $APP_ID v$VERSION, echipa $TEAM_ID)."
