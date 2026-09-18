#!/bin/bash
# Starea motorului GDC Firewall, fără root și fără nicio modificare.
#   ./scripts/engine-status.sh
# (Înlocuiește repair-engine.sh: `bootout` pe jobul NOU îi șterge și
# înregistrarea providerului, iar macOS nu-l retrimite până la o activare sau
# repornire — verificat 2026-09-18. Reparația corectă e înlocuirea secvențială
# din aplicație; vezi EngineService.swift.)
set -uo pipefail
MACH="8AR6XP8MG7.dev.gordas.GDCFirewall"
PREFS="/Library/Application Support/GDC Firewall/preferences.plist"
APP_EXT="/Applications/GDC Firewall.app/Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension/Contents/Info.plist"

LABELS="$(grep -oE 'NetworkExtension\.dev\.gordas\.GDCFirewall\.extension\.[0-9.]+' < <(launchctl print system 2>/dev/null) | sort -u)"
BUNDLED=""
[ -f "$APP_EXT" ] && BUNDLED="NetworkExtension.dev.gordas.GDCFirewall.extension.$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_EXT").$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_EXT")"
echo "Extensie în aplicație: ${BUNDLED:-—}"
if [ -z "$LABELS" ]; then
  echo "✗ Niciun job al extensiei în launchd (filtrul oprit, neaprobat, sau înregistrarea pierdută → repornirea Mac-ului)."
  EXIT=2
else
  EXIT=0
  while IFS= read -r L; do
    if grep -q 'active = 1' < <(grep -A6 "\"$MACH\" = {" < <(launchctl print "system/$L" 2>/dev/null)); then
      echo "✓ $L deține serviciul Mach"
    else
      echo "✗ $L rulează FĂRĂ serviciul Mach (cursa de înlocuire → repornirea Mac-ului)"; EXIT=1
    fi
  done <<< "$LABELS"
  [ -n "$BUNDLED" ] && ! grep -qx "$BUNDLED" <<< "$LABELS" && echo "ℹ Rulează altă versiune decât cea din aplicație (înlocuire amânată sau în curs)."
fi
if [ -r "$PREFS" ]; then
  P="$(/usr/libexec/PlistBuddy -c 'Print :passiveMode' "$PREFS" 2>/dev/null || echo false)"
  A="$(/usr/libexec/PlistBuddy -c 'Print :passiveModeAction' "$PREFS" 2>/dev/null || echo 0)"
  if [ "$P" = true ] && [ "$A" = 1 ]; then echo "ℹ Garda de actualizare activă: conexiunile necunoscute sunt blocate până se conectează aplicația."; fi
fi
exit $EXIT
