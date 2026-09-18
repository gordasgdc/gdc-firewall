#!/bin/bash
# Scriptul de lansare: compilează, asamblează „GDC Firewall.app”, semnează,
# împachetează arhiva de test și aliniază versiunile.
#
# Semnare: dacă APPLE_SIGN_IDENTITY_APP e setată, se semnează Developer ID
# cu entitlement-urile de NetworkExtension; altfel, semnare ad-hoc pentru
# testare locală. Ad-hoc e suficient ca aplicația să pornească, dar NU e
# suficient ca extensia de rețea să se încarce — vezi avertismentul final.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT/macOS/GDCFirewall"
APP_NAME="GDC Firewall.app"
BUILD_OUT="$ROOT/Build/macOS"
APP_PATH="$BUILD_OUT/$APP_NAME"
ENTITLEMENTS="$PKG_DIR/codesigning/GDCFirewall.entitlements"

# 0. Motorul trebuie să fie prezent și NEATINS înainte de orice build.
bash "$ROOT/scripts/fetch-engine.sh"
bash "$ROOT/scripts/check-l10n.sh"

echo "→ Compilare release (swift build -c release)…"
cd "$PKG_DIR"
swift build -c release

BIN_PATH="$PKG_DIR/.build/release/GDCFirewall"
BUNDLE_PATH="$(find -L "$PKG_DIR/.build/release" -maxdepth 1 -name "*.bundle" | head -n1)"

echo "→ Asamblare ${APP_NAME}…"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

# Build number, incrementat automat — distinct de versiunea semantică
# (CFBundleShortVersionString), care se ridică manual, cu intenție (Regula 14).
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PKG_DIR/Resources/Info.plist" 2>/dev/null || echo 0)
NEXT_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PKG_DIR/Resources/Info.plist"
echo "→ Build number: $NEXT_BUILD"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/GDCFirewall"
cp "$PKG_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
[ -n "$BUNDLE_PATH" ] && cp -R "$BUNDLE_PATH" "$APP_PATH/Contents/Resources/"

# Manifestul GDC stă ÎN bundle, niciodată liber lângă .app în arhivă.
mkdir -p "$APP_PATH/Contents/Resources/GDC"
cp "$ROOT/gdc-manifest.json" "$APP_PATH/Contents/Resources/GDC/"

# Atribuirea GPL-3.0 călătorește cu binarul, nu doar cu repo-ul: cine
# primește arhiva trebuie să vadă licența și autorul motorului.
cp "$ROOT/NOTICE.md" "$APP_PATH/Contents/Resources/"
[ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$APP_PATH/Contents/Resources/"

ICONSET_SRC="$PKG_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET_SRC" ] && ls "$ICONSET_SRC"/icon_*.png >/dev/null 2>&1; then
  echo "→ Generare AppIcon.icns…"
  ICONSET_TMP="$BUILD_OUT/AppIcon.iconset"
  rm -rf "$ICONSET_TMP"; mkdir -p "$ICONSET_TMP"
  cp "$ICONSET_SRC"/icon_*.png "$ICONSET_TMP/"
  iconutil -c icns "$ICONSET_TMP" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_TMP"
else
  echo "→ ⚠️  Nicio iconiță în Assets.xcassets/AppIcon.appiconset — bundle-ul rămâne cu pictograma implicită."
fi

if [ -n "${APPLE_SIGN_IDENTITY_APP:-}" ]; then
  # Delegat, nu făcut aici: o aplicație cu extensie de sistem are DOUĂ
  # bundle-uri cu entitlements diferite, semnate dinăuntru spre afară.
  # Vezi codesigning/sign-and-notarize.sh pentru de ce `--deep` e greșit aici.
  echo "→ Semnare Developer ID (aplicație + extensie de sistem)…"
  "$PKG_DIR/codesigning/sign-and-notarize.sh" app "$APP_PATH"
  SIGNED="developer-id"
else
  echo "→ Semnare ad-hoc (setează APPLE_SIGN_IDENTITY_APP pentru semnare reală)…"
  codesign --force --deep -s - "$APP_PATH"
  SIGNED="ad-hoc"
fi

# Regula 0: versiunea raportată e cea din bundle-ul CONSTRUIT, nu cea din surse.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")

echo "→ Împachetare arhivă de test…"
DIST_DIR="$ROOT/dist"
ZIP_NAME="GDCFirewall-macOS-$VERSION.zip"   # Regula 17: versiunea în NUMELE fișierului.
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME"
STAGE="$BUILD_OUT/_staging"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
# Regula 6 — arhiva are la rădăcină EXACT: .app, dezinstalator, PDF.
cp "$PKG_DIR/Dezinstalare_GDCFirewall.command" "$STAGE/"
# Ghidul se regenerează la fiecare build, din cod: un PDF vechi în arhivă ar
# descrie butoane care nu mai există.
swift "$ROOT/installer/generate-guide.swift"
if [ -f "$ROOT/installer/Instructiuni_Utilizare.pdf" ]; then
  cp "$ROOT/installer/Instructiuni_Utilizare.pdf" "$STAGE/"
else
  echo "→ ⚠️  Instructiuni_Utilizare.pdf lipsește — arhiva NU respectă încă Regula 6."
fi
(cd "$STAGE" && zip -qr "$DIST_DIR/$ZIP_NAME" .)
rm -rf "$STAGE"

SHA256=$(shasum -a 256 "$DIST_DIR/$ZIP_NAME" | awk '{print $1}')

# Versiunea se ține sincronă în toate punctele care o poartă (Regula 14).
python3 - "$ROOT" "$VERSION" <<'PY'
import json, pathlib, sys
root, version = pathlib.Path(sys.argv[1]), sys.argv[2]
for name, key in (("gdc-manifest.json", "version"), ("docs/update.json", "version")):
    path = root / name
    data = json.loads(path.read_text())
    data[key] = version
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(f"→ gdc-manifest.json și docs/update.json aliniate la {version}")
PY

bash "$ROOT/scripts/sync-site.sh" || echo "→ ⚠️  Sincronizarea site-ului a eșuat — vezi eroarea de mai sus."

echo
echo "✅ Gata: $APP_PATH (v$VERSION, build $NEXT_BUILD, semnare: $SIGNED)"
echo "   Arhivă: $DIST_DIR/$ZIP_NAME"
echo "   sha256: $SHA256"
echo
if [ "$SIGNED" = "ad-hoc" ]; then
  echo "⚠️  Cu semnare ad-hoc aplicația PORNEȘTE, dar extensia de rețea NU se"
  echo "    încarcă: macOS cere o semnătură Developer ID cu entitlement-ul"
  echo "    com.apple.developer.networking.networkextension. Până când Apple îl"
  echo "    aprobă pe cont, testează interfața (alerte, reguli, blocklist), nu"
  echo "    filtrarea reală."
fi
