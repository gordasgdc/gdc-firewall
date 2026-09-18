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

HREF="$(grep -oE 'class="btn" href="[^"]+"' < <(curl -fsS "$BASE/") | head -1 | sed 's/.*href="//; s/"$//')"
case "$HREF" in
  *github.com*|"") bad "butonul de descărcare: „${HREF:-lipsă}”" ;;
  http*) URL="$HREF" ;;
  *) URL="$BASE/$HREF" ;;
esac
[ -n "${URL:-}" ] || { echo "Oprit."; exit 1; }

JSON="$(curl -fsS -H 'Cache-Control: no-cache' "$BASE/update.json")" || { bad "update.json inaccesibil"; exit 1; }
read -r JV JURL < <(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); u=d["download_url"]; print(d["version"], u["mac"] if isinstance(u,dict) else u)' "$JSON")
[ "$JURL" = "$URL" ] && ok "update.json și butonul paginii indică aceeași arhivă: $URL" || bad "update.json → $JURL, butonul → $URL"
[ -n "${1:-}" ] && { [ "$JV" = "$1" ] && ok "update.json anunță $JV" || bad "update.json anunță $JV, nu $1"; }

read -r CODE REDIRS TYPE < <(curl -sS -o "$WORK/a.zip" -w '%{http_code} %{num_redirects} %{content_type}\n' -L "$URL")
[ "$CODE" = 200 ] && [ "$REDIRS" = 0 ] && ok "arhiva: HTTP 200, 0 redirecționări, $TYPE, $(du -h "$WORK/a.zip" | cut -f1)" \
  || bad "arhiva: HTTP $CODE, $REDIRS redirecționări"
ditto -x -k "$WORK/a.zip" "$WORK/x" 2>/dev/null || { bad "arhiva nu se dezarhivează"; exit 1; }
N="$(find "$WORK/x" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
[ "$N" = 3 ] && ok "exact 3 fișiere la rădăcină" || bad "$N fișiere la rădăcină (Regula 6 cere 3)"
APP="$WORK/x/GDC Firewall.app"
ZV="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
[ "$ZV" = "$JV" ] && ok "versiunea din arhivă = update.json = $ZV" || bad "arhiva conține ${ZV:-?}, update.json anunță $JV"
[ -d "$APP/Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension" ] && ok "conține extensia de rețea" || bad "fără extensie de rețea"
codesign --verify --strict --deep "$APP" 2>/dev/null && ok "semnătură validă" || bad "semnătură invalidă"
xcrun stapler validate "$APP" >/dev/null 2>&1 && ok "notarizată, bilet stapled" || bad "fără bilet de notarizare"
exit $FAIL
