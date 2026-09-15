#!/bin/bash
# Regenerează AppIcon.appiconset din Resources/AppIcon.svg.
# Rulat manual, la fiecare schimbare a sursei vectoriale — build_app.sh doar
# consumă PNG-urile, nu le reconstruiește (un build n-are de ce să rescrie
# fișiere urmărite în git).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/macOS/GDCFirewall/Resources/AppIcon.svg"
OUT="$ROOT/macOS/GDCFirewall/Resources/Assets.xcassets/AppIcon.appiconset"

echo "→ Generez pictograma din $(basename "$SRC")…"
swift "$ROOT/scripts/make-appicon.swift" "$SRC" "$OUT"

# Verificare, nu presupunere: iconutil refuză un iconset incomplet, așa că
# îl construim aici o dată, ca eroarea să apară acum, nu în timpul unui build.
TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$TMP"
cp "$OUT"/icon_*.png "$TMP/"
iconutil -c icns "$TMP" -o "$TMP/../AppIcon.icns"
echo "✓ iconutil acceptă setul ($(du -h "$TMP/../AppIcon.icns" | cut -f1) .icns)."
rm -rf "$(dirname "$TMP")"
