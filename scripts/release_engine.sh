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

# --- 5. DMG semnat + notarizat + stapled (înlocuiește arhiva .zip) --------
DMG="$DIST/GDCFirewall-macOS-${VERSION}.dmg"
SIGN_ID="${SIGN_IDENTITY:-Developer ID Application: DUMITRU CRISTINEL GORDAS (8AR6XP8MG7)}"
STAGE="$WORK/stage"
mkdir -p "$STAGE" "$DIST"
ditto "$APP" "$STAGE/GDC Firewall.app"
cp "$ROOT/installer/Instructiuni_Utilizare.pdf" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "GDC Firewall ${VERSION}" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null \
  || fail "hdiutil create a eșuat"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG" || fail "Semnarea DMG a eșuat"
echo "→ Notarizez DMG-ul…"
OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json)" || fail "notarytool (DMG) a eșuat"
STATUS="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
ID="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
[ "$STATUS" = "Accepted" ] || { xcrun notarytool log "$ID" --keychain-profile "$PROFILE" 2>/dev/null | head -40 >&2; fail "DMG respins (${STATUS})"; }
xcrun stapler staple "$DMG" >/dev/null || fail "stapler staple (DMG) a eșuat"
xcrun stapler validate "$DMG" >/dev/null || fail "stapler validate (DMG) a eșuat"
grep -q "Notarized Developer ID" < <(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1) \
  || fail "Gatekeeper nu acceptă DMG-ul: $(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -2)"

# --- 6. Verificare ca un client: montare, aplicație, extensie, versiune ----
MNT="$WORK/mnt"; mkdir -p "$MNT"
hdiutil attach "$DMG" -mountpoint "$MNT" -nobrowse -readonly >/dev/null || fail "DMG nu se montează"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null; rm -rf "$WORK"' EXIT
CHECKED_APP="$MNT/GDC Firewall.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CHECKED_APP/Contents/Info.plist")" = "$VERSION" ] || fail "Versiunea din DMG diferă de ${VERSION}"
[ -d "$CHECKED_APP/Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension" ] || fail "DMG-ul nu conține extensia de rețea"
codesign --verify --strict --deep "$CHECKED_APP" || fail "Semnătura aplicației din DMG nu e validă"
xcrun stapler validate "$CHECKED_APP" >/dev/null || fail "Aplicația din DMG nu are biletul de notarizare"
grep -q "Notarized Developer ID" < <(spctl -a -vv -t exec "$CHECKED_APP" 2>&1) || fail "Gatekeeper respinge aplicația din DMG"

echo "✓ ${DMG##*/}: semnat, notarizat, stapled, acceptat de Gatekeeper"
echo "  sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
