#!/bin/bash
# Verifică LIVE ce descarcă un client de pe gordas.dev/gdc-firewall:
#   - butonul paginii duce direct la arhivă (fără GitHub, fără redirecționări);
#   - update.json și arhiva servită au ACEEAȘI versiune;
#   - arhiva: exact 3 fișiere, aplicație cu extensie, semnată, notarizată (stapled).
#   ./scripts/verify-download.sh [versiune-așteptată]
set -uo pipefail
BASE="https://gordas.dev/gdc-firewall"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAIL=0
ok()  { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

HREF="$(grep -oE 'id="download" href="[^"]+"' < <(curl -fsS "$BASE/") | head -1 | sed 's/.*href="//; s/"$//')"
case "$HREF" in
  *github.com*|"") bad "butonul de descărcare: „${HREF:-lipsă}”" ;;
  http*) URL="$HREF" ;;
  *) URL="$BASE/$HREF" ;;
esac
[ -n "${URL:-}" ] || { echo "Oprit."; exit 1; }

JSON="$(curl -fsS -H 'Cache-Control: no-cache' "$BASE/update.json")" || { bad "update.json inaccesibil"; exit 1; }
read -r JV JURL < <(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); u=d["download_url"]; print(d["version"], u["mac"] if isinstance(u,dict) else u)' "$JSON")
JDMG="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["download_url"].get("mac_dmg",""))' "$JSON")"
[ "$JDMG" = "$URL" ] && ok "update.json (mac_dmg) și butonul paginii indică același DMG: $URL" || bad "update.json mac_dmg → $JDMG, butonul → $URL"
case "$JURL" in *"/GDCFirewall-macOS-$JV.zip") ok "canal updater vechi: $JURL" ;; *) bad "update.json mac nu e zip-ul versionat: $JURL" ;; esac
ZC="$(curl -sS -o /dev/null -w '%{http_code}' -L "$JURL")"
[ "$ZC" = 200 ] && ok "zip updater: HTTP 200" || bad "zip updater: HTTP $ZC"
[ -n "${1:-}" ] && { [ "$JV" = "$1" ] && ok "update.json anunță $JV" || bad "update.json anunță $JV, nu $1"; }
case "$URL" in *"/GDCFirewall-macOS-$JV.dmg") ok "numele arhivei poartă versiunea: ${URL##*/}" ;; *) bad "numele arhivei nu poartă versiunea $JV: ${URL##*/}" ;; esac
STABLE="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/GDCFirewall-macOS.dmg")"
[ "$STABLE" = 200 ] && ok "copia cu nume stabil rămâne publicată (Regula 17)" || bad "GDCFirewall-macOS.dmg: HTTP $STABLE"

read -r CODE REDIRS TYPE < <(curl -sS -o "$WORK/a.dmg" -w '%{http_code} %{num_redirects} %{content_type}\n' -L "$URL")
[ "$CODE" = 200 ] && [ "$REDIRS" = 0 ] && ok "arhiva: HTTP 200, 0 redirecționări, $TYPE, $(du -h "$WORK/a.dmg" | cut -f1)" \
  || bad "arhiva: HTTP $CODE, $REDIRS redirecționări"
mkdir -p "$WORK/x"
hdiutil attach "$WORK/a.dmg" -mountpoint "$WORK/x" -nobrowse -readonly -quiet || { bad "DMG-ul nu se montează"; exit 1; }
trap 'hdiutil detach "$WORK/x" -quiet 2>/dev/null' EXIT
APP="$WORK/x/GDC Firewall.app"
ZV="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
[ "$ZV" = "$JV" ] && ok "versiunea din DMG = update.json = $ZV" || bad "DMG conține ${ZV:-?}, update.json anunță $JV"
[ -d "$APP/Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension" ] && ok "conține extensia de rețea" || bad "fără extensie de rețea"
codesign --verify --strict --deep "$APP" 2>/dev/null && ok "semnătură validă" || bad "semnătură invalidă"
xcrun stapler validate "$WORK/a.dmg" >/dev/null 2>&1 && ok "DMG notarizat, bilet stapled" || bad "DMG fără bilet de notarizare"
exit $FAIL
