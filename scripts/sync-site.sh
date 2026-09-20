#!/bin/bash
# Copiaza docs/ (pagina de prezentare + update.json) in repo-ul site-ului,
# la gordas.dev/gdc-firewall.
#
# De ce nu GitHub Pages pe ACEST repo: domeniul gordas.dev e deja revendicat
# (CNAME) de `gdc-plugin-manager-catalog-vendor`, iar un domeniu apex poate
# apartine unui singur repo. Pagina noastra e o subcale a aceluiasi site,
# exact ca celelalte aplicatii GDC.
#
# NU face git commit/push singur — asta ar fi o actiune pe alt repo, vazuta
# abia dupa ce s-a intamplat. Commit-ul ramane un pas separat si explicit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_REPO="$ROOT/../gdc-plugin-manager-catalog-vendor"
SITE_DIR="$VENDOR_REPO/docs/gdc-firewall"

# Versiunea aplicatiei: din bundle, nu dintr-o constanta scrisa aici
# (Regula 0 — sursa de adevar e ce se instaleaza, nu ce zice codul).
PLIST="$ROOT/macOS/GDCFirewall/Resources/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"

# ---------------------------------------------------------------------------
# Versiunea motorului: citita din repo-ul LuLu CLONAT, nu dintr-o valoare
# scrisa de mana. Manifestul de pe server anunta clientilor ce motor mai e
# sustinut; daca numarul ala ar fi tastat separat, ar diverge de codul
# livrat exact in momentul in care conteaza — la un update de securitate.
# ---------------------------------------------------------------------------
ENGINE_DIR="$ROOT/Engine/LuLu"
if [ ! -d "$ENGINE_DIR/.git" ]; then
  echo "‼️  Engine/LuLu lipseste — ruleaza intai scripts/fetch-engine.sh."
  echo "    Fara el nu pot sti ce versiune de motor sa anunt in update.json."
  exit 1
fi
ENGINE_TAG="$(git -C "$ENGINE_DIR" describe --tags --always)"
ENGINE_VERSION="${ENGINE_TAG#v}"          # "v4.5.1" -> "4.5.1"

# Aceeasi valoare trebuie sa fie si in cod: aplicatia se compara pe sine cu
# manifestul folosind LuLu.engineVersion.
CODE_ENGINE="$(sed -n 's/.*static let engineVersion = "\(.*\)".*/\1/p' \
  "$ROOT/macOS/GDCFirewall/Sources/GDCFirewall/Engine/LuLuConstants.swift")"
if [ "$CODE_ENGINE" != "$ENGINE_VERSION" ]; then
  echo "‼️  Motor clonat: $ENGINE_VERSION, dar LuLuConstants.swift zice $CODE_ENGINE."
  echo "    Aplicatia ar raporta un motor pe care nu-l are. Aliniaza-le."
  exit 1
fi

if [ ! -d "$VENDOR_REPO" ]; then
  echo "→ ⚠️  $VENDOR_REPO nu exista — sar peste sincronizarea site-ului."
  exit 0
fi

# Arhiva de distributie, direct de pe gordas.dev. Butonul paginii si
# update.json duc la numele VERSIONAT (un client care redescarca nu mai ajunge
# la „GDCFirewall-macOS (1).zip” si stie ce versiune are pe disc). Copia cu nume
# stabil ramane publicata alaturi (Regula 17), pentru linkuri fixe.
ZIP_NAME="GDCFirewall-macOS-$APP_VERSION.dmg"
ZIP="$ROOT/dist/$ZIP_NAME"
if [ ! -f "$ZIP" ]; then
  echo "‼️  $ZIP lipseste — ruleaza intai ./scripts/release_engine.sh."
  echo "    Fara ea, butonul paginii ar duce la un 404."
  exit 1
fi
mkdir -p "$SITE_DIR"
sed -i '' -E "s#(id=\"download\" href=\")GDCFirewall-macOS[^\"]*\.(zip|dmg)\"#\1$ZIP_NAME\"#" "$ROOT/docs/index.html"
grep -q "id=\"download\" href=\"$ZIP_NAME\"" "$ROOT/docs/index.html" \
  || { echo "‼️  Nu am putut scrie linkul versionat in docs/index.html"; exit 1; }
cp "$ROOT/docs/index.html" "$SITE_DIR/index.html"
cp "$ZIP" "$SITE_DIR/$ZIP_NAME"
cp "$ZIP" "$SITE_DIR/GDCFirewall-macOS.dmg"

# Canal de compatibilitate pentru Self-Updater-ul instalarilor <= 2.3.3, care
# stie doar .zip/.pkg (pe .dmg ar rula `installer -pkg` si ar esua). Zip-ul
# se face din aplicatia din DMG-ul notarizat; il descarca doar updaterul
# (URLSession, fara browser), nu clientul. Butonul paginii ramane DMG.
UPD_ZIP_NAME="GDCFirewall-macOS-$APP_VERSION.zip"
MNT="$(mktemp -d)"; UZ="$(mktemp -d)"
hdiutil attach "$ZIP" -mountpoint "$MNT" -nobrowse -readonly -quiet
ditto "$MNT/GDC Firewall.app" "$UZ/GDC Firewall.app"
hdiutil detach "$MNT" -quiet
rm -f "$SITE_DIR/$UPD_ZIP_NAME"
(cd "$UZ" && ditto -c -k --sequesterRsrc . "$SITE_DIR/$UPD_ZIP_NAME")
rm -rf "$UZ" "$MNT"
cp "$SITE_DIR/$UPD_ZIP_NAME" "$SITE_DIR/GDCFirewall-macOS.zip"

python3 - "$ROOT/docs/update.json" "$SITE_DIR/update.json" "$APP_VERSION" "$ENGINE_VERSION" <<'PY'
import json, pathlib, sys
src, dst, app_version, engine_version = sys.argv[1:5]

data = json.loads(pathlib.Path(src).read_text())
data["app_version"] = app_version
# `version` ramane pentru totdeauna, sinonim cu `app_version` (Regula 35):
# un client publicat care-l decodeaza ca obligatoriu ar esua tacit fara el.
data["version"] = app_version
data["engine_version_required"] = engine_version
# Tipul campului ramane dictionar {mac: url} (Regula 35); doar numele arhivei
# poarta acum versiunea.
data["download_url"] = {
    # `mac` ramane .zip: Self-Updater-ul <= 2.3.3 nu instaleaza .dmg. Cel nou le stie pe ambele.
    "mac": f"https://gordas.dev/gdc-firewall/GDCFirewall-macOS-{app_version}.zip",
    "mac_dmg": f"https://gordas.dev/gdc-firewall/GDCFirewall-macOS-{app_version}.dmg",
}

for path in (src, dst):
    pathlib.Path(path).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY

echo "✓ Site sincronizat la $SITE_DIR"
echo "  aplicatie $APP_VERSION · motor $ENGINE_VERSION"
echo "  Pas urmator, manual: commit + push in gdc-plugin-manager-catalog-vendor."
