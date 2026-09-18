#!/bin/bash
# Release-ul build-ului COMPLET (aplicație + extensie de rețea), gata de publicat:
#
#   1. build_engine_app.sh — compilare + semnare Developer ID + toate verificările
#   2. notarizare Apple (profilul Keychain `gdc-notary`, ca în restul
#      ecosistemului — parola nu trece prin script)
#   3. staple + verificare Gatekeeper (spctl: „Notarized Developer ID”)
#   4. ghidul PDF regenerat din cod
#   5. arhiva de client cu EXACT 3 fișiere (Regula 6), versiunea în nume (Regula 17):
#        dist/GDCFirewall-macOS-<versiune>.zip
#   6. verificarea arhivei după dezarhivare, ca pe Mac-ul clientului
#
# Publicarea pe gordas.dev rămâne pasul separat `scripts/sync-site.sh` + commit
# în gdc-plugin-manager-catalog-vendor.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-gdc-notary}"
APP="$ROOT/Build/engine/Release/GDC Firewall.app"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/macOS/GDCFirewall/Resources/Info.plist")"
ZIP="$DIST/GDCFirewall-macOS-${VERSION}.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "‼️  $*" >&2; exit 1; }

# --- 1. Build + verificări ------------------------------------------------
bash "$ROOT/scripts/build_engine_app.sh" >/dev/null || fail "build_engine_app.sh a eșuat — rulează-l direct pentru detalii."
echo "✓ Build ${VERSION} semnat și verificat"

# --- 2. Notarizare --------------------------------------------------------
echo "→ Trimit la notarizare Apple (1–15 min)…"
ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
OUT="$(xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$PROFILE" --wait --output-format json)" \
  || fail "notarytool a eșuat. Profilul „${PROFILE}” există? (xcrun notarytool history --keychain-profile ${PROFILE})"
STATUS="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
ID="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
if [ "$STATUS" != "Accepted" ]; then
  xcrun notarytool log "$ID" --keychain-profile "$PROFILE" 2>/dev/null | head -40 >&2
  fail "Notarizare respinsă (${STATUS}, id ${ID})."
fi
echo "✓ Notarizat (id ${ID})"

# --- 3. Staple + Gatekeeper -----------------------------------------------
xcrun stapler staple "$APP" >/dev/null || fail "stapler staple a eșuat"
xcrun stapler validate "$APP" >/dev/null || fail "stapler validate a eșuat"
grep -q "Notarized Developer ID" < <(spctl -a -vv -t exec "$APP" 2>&1) \
  || fail "Gatekeeper nu acceptă aplicația: $(spctl -a -vv -t exec "$APP" 2>&1 | head -2)"
echo "✓ Stapled, acceptată de Gatekeeper (Notarized Developer ID)"

# --- 4. Ghidul ------------------------------------------------------------
swift "$ROOT/installer/generate-guide.swift" >/dev/null || fail "Ghidul PDF nu s-a generat"

# --- 5. Arhiva de client (Regula 6: exact 3 fișiere) ----------------------
STAGE="$WORK/stage"
mkdir -p "$STAGE" "$DIST"
ditto "$APP" "$STAGE/GDC Firewall.app"
cp "$ROOT/macOS/GDCFirewall/Dezinstalare_GDCFirewall.command" "$STAGE/"
cp "$ROOT/installer/Instructiuni_Utilizare.pdf" "$STAGE/"
rm -f "$ZIP"
(cd "$STAGE" && ditto -c -k --sequesterRsrc . "$ZIP")

# --- 6. Verificarea arhivei, ca un client --------------------------------
CHECK="$WORK/check"
ditto -x -k "$ZIP" "$CHECK"
COUNT="$(find "$CHECK" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
[ "$COUNT" = "3" ] || fail "Arhiva are ${COUNT} elemente la rădăcină, nu 3."
CHECKED_APP="$CHECK/GDC Firewall.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CHECKED_APP/Contents/Info.plist")" = "$VERSION" ] \
  || fail "Versiunea din arhivă diferă de ${VERSION}"
[ -d "$CHECKED_APP/Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension" ] \
  || fail "Arhiva nu conține extensia de rețea"
codesign --verify --strict --deep "$CHECKED_APP" || fail "Semnătura aplicației din arhivă nu e validă"
xcrun stapler validate "$CHECKED_APP" >/dev/null || fail "Aplicația din arhivă nu are biletul de notarizare"

echo "✓ ${ZIP##*/}: aplicație + extensie, notarizată și stapled, dezinstalator, ghid PDF"
echo "  sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "  Publicare: ./scripts/sync-site.sh, apoi commit + push în gdc-plugin-manager-catalog-vendor."
