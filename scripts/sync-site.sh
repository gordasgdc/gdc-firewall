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

if [ ! -d "$VENDOR_REPO" ]; then
  echo "→ ⚠️  $VENDOR_REPO nu exista — sar peste sincronizarea site-ului."
  exit 0
fi

mkdir -p "$SITE_DIR"
cp "$ROOT/docs/index.html" "$SITE_DIR/index.html"
cp "$ROOT/docs/update.json" "$SITE_DIR/update.json"

# Versiunea din update.json trebuie sa fie cea INSTALABILA, nu cea din surse
# (Regula 0): o citim din Info.plist-ul pachetului, nu dintr-o constanta.
PLIST="$ROOT/macOS/GDCFirewall/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
SITE_VERSION="$(python3 -c "import json,sys;print(json.load(open('$SITE_DIR/update.json'))['version'])")"

if [ "$VERSION" != "$SITE_VERSION" ]; then
  echo "‼️  Info.plist zice $VERSION, dar docs/update.json zice $SITE_VERSION."
  echo "    Aliniaza-le inainte de publicare (Regula 14)."
  exit 1
fi

echo "✓ Site sincronizat la $SITE_DIR (versiunea $VERSION)."
echo "  Pas urmator, manual: commit + push in gdc-plugin-manager-catalog-vendor."
