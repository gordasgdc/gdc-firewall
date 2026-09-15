#!/bin/bash
# Dezinstalare completă GDC Firewall (Regula 6 din Standardul GDC).
# Dublu-click pe acest fișier în Finder.
set -u

APP="/Applications/GDC Firewall.app"
BUNDLE_ID="dev.gordas.GDCFirewall"

echo "Dezinstalare GDC Firewall…"
echo

# 1. Oprim aplicația.
pkill -f "GDC Firewall" 2>/dev/null || true
sleep 1

# 2. Extensia de sistem. `systemextensionsctl uninstall` cere Team ID-ul și
#    nu poate rula neinteractiv fără SIP dezactivat — de aia dezinstalarea
#    curată a extensiei trece prin aplicație (meniul ei) sau prin Setări de
#    sistem → General → Elemente de conectare și extensii. O semnalăm
#    explicit, nu o ascundem sub un `|| true` tăcut.
if systemextensionsctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
  echo "⚠️  Extensia de rețea e încă instalată."
  echo "    Scoate-o din Setări de sistem → General → Elemente de conectare"
  echo "    și extensii → Extensii de rețea, apoi rulează din nou acest script."
fi

# 3. Fișierele.
rm -rf "$APP"
rm -rf "$HOME/Library/Application Support/GDCFirewall"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID"
rm -f  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
rm -rf "$HOME/Library/Logs/GDCFirewall"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo
echo "✅ GDC Firewall a fost dezinstalat."
echo "   Motorul LuLu, dacă l-ai instalat separat, rămâne neatins."
read -n 1 -s -r -p "Apasă orice tastă pentru a închide."
