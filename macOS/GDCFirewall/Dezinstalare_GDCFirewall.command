#!/bin/bash
# Dezinstalare completă GDC Firewall (Regula 6). Dublu-click în Finder.
#
# Funcționează oriunde s-ar afla aplicația (Aplicații, Downloads, alt nume) și
# chiar dacă a fost deja ștearsă. Scoate: extensia de rețea
# (dev.gordas.GDCFirewall.extension), configurația de filtru din Setări →
# Rețea, regulile motorului, preferințele, cache-urile, logurile, toate copiile
# aplicației. Nu atinge un LuLu sau Little Snitch instalat separat.
#
#   ./Dezinstalare_GDCFirewall.command --dry-run   # doar arată ce ar face
set -u

BUNDLE_ID="dev.gordas.GDCFirewall"
EXT_ID="dev.gordas.GDCFirewall.extension"
TEAM_ID="8AR6XP8MG7"
APP_NAME="GDC Firewall.app"
MIN_UNINSTALL="2.3.3"   # prima versiune care știe --uninstall-extension
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAILED=0

say()  { echo "$*"; }
step() { echo; echo "── $* ──"; }
run_root() {  # comandă cu drepturi de administrator, afișată înainte
  if [ "$DRY" = 1 ]; then say "  [dry-run] sudo $*"; return 0; fi
  sudo "$@"
}

version_ge() {  # $1 >= $2, numeric pe componente
  local IFS=.
  local -a a=($1) b=($2)
  local i x y
  for i in 0 1 2; do
    x="${a[$i]:-0}"; y="${b[$i]:-0}"
    [ "$((10#$x))" -gt "$((10#$y))" ] && return 0
    [ "$((10#$x))" -lt "$((10#$y))" ] && return 1
  done
  return 0
}

app_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null; }

# Toate copiile, după bundle ID (nu după nume): Spotlight + locurile obișnuite.
# Build-urile de dezvoltare și copiile de pe alte volume (backup) nu se ating.
find_apps() {
  {
    mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null
    for p in "/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME" "$SCRIPT_DIR/$APP_NAME"; do
      [ -d "$p" ] && echo "$p"
    done
    find "$HOME/Downloads" "$HOME/Desktop" -maxdepth 3 -type d -name 'GDC Firewall*.app' 2>/dev/null
  } | sort -u | while IFS= read -r p; do
    case "$p" in
      "$HOME/Developer/"*|*/Build/engine/*|*/DerivedData/*|*/.build/*|/Volumes/*|"$HOME/.Trash/"*|*/AppTranslocation/*) continue ;;
    esac
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$p/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] && echo "$p"
  done
}

ext_states() { grep -F "$EXT_ID" < <(systemextensionsctl list 2>/dev/null) | grep -oE '\[[^]]+\]$' | sort | uniq -c; }
ext_active() { grep -F "$EXT_ID" < <(systemextensionsctl list 2>/dev/null) | grep -c '\[activated'; }
ne_config()  { grep -c "$BUNDLE_ID" < <(plutil -p /Library/Preferences/com.apple.networkextension.plist 2>/dev/null); }

USER_ITEMS=(
  "$HOME/Library/Application Support/GDCFirewall"
  "$HOME/Library/Caches/$BUNDLE_ID"
  "$HOME/Library/HTTPStorages/$BUNDLE_ID"
  "$HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies"
  "$HOME/Library/WebKit/$BUNDLE_ID"
  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
  "$HOME/Library/Logs/GDCFirewall"
  "$HOME/Library/Logs/GDCFirewall.log"
  "$HOME/Library/Logs/GDCFirewall.log.1"
  "$HOME/Library/Logs/GDCFirewall-cleanup.log"
)
ROOT_ITEMS=("/Library/Application Support/GDC Firewall")

existing_files() {
  local p
  for p in "${USER_ITEMS[@]}" "${ROOT_ITEMS[@]}"; do [ -e "$p" ] && echo "$p"; done
  ls -d "$HOME/Library/Preferences/ByHost/$BUNDLE_ID".*.plist 2>/dev/null
  ls -d "$(getconf DARWIN_USER_TEMP_DIR)"gdcfirewall-update-* 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
echo "Dezinstalare GDC Firewall$([ "$DRY" = 1 ] && echo " — PREVIZUALIZARE, nu se modifică nimic")"

step "Ce am găsit"
find_apps > "$WORK/apps"
existing_files > "$WORK/files"
say "Copii ale aplicației: $(grep -c . "$WORK/apps")"
while IFS= read -r p; do say "  • $p ($(app_version "$p"))"; done < "$WORK/apps"
say "Extensia de rețea:"; ext_states | sed 's/^/  /'; [ -z "$(ext_states)" ] && say "  —"
say "Configurație de filtru în Setări → Rețea: $([ "$(ne_config)" -gt 0 ] && echo prezentă || echo —)"
say "Fișiere: $(grep -c . "$WORK/files")"
while IFS= read -r p; do say "  • $p"; done < "$WORK/files"

if [ "$DRY" = 0 ]; then
  echo
  echo "Unele fișiere aparțin sistemului: macOS îți cere parola de administrator"
  echo "(nu se vede nimic cât o tastezi — apasă Enter la final)."
  sudo -v || { echo "Fără parolă nu pot continua. Nimic nu a fost modificat."; exit 1; }
fi

# ─────────────────────────────────────────────────────────────────────────────
step "1. Închid aplicația"
if [ "$DRY" = 0 ]; then
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  sleep 2
fi
# După calea executabilului — inclusiv copii izolate (App Translocation) sau redenumite.
while read -r pid comm; do
  case "$comm" in
    */Contents/MacOS/"GDC Firewall")
      if [ "$DRY" = 1 ]; then say "  [dry-run] opresc $pid $comm"; else kill "$pid" 2>/dev/null && say "  ✓ oprit $pid"; fi ;;
  esac
done < <(ps -axo pid=,comm=)
say "  gata"

# ─────────────────────────────────────────────────────────────────────────────
step "2. Extensia de rețea și filtrul"
if [ "$(ext_active)" -gt 0 ] || [ "$(ne_config)" -gt 0 ]; then
  # Singura cale oficială (cu SIP activ): aplicația care conține extensia o
  # dezactivează. O copie suficient de nouă, pusă în /Applications dacă e nevoie.
  UNINSTALLER=""
  while IFS= read -r p; do
    v="$(app_version "$p")"; [ -n "$v" ] && version_ge "$v" "$MIN_UNINSTALL" || continue
    if [ -z "$UNINSTALLER" ] || [ "$p" = "/Applications/$APP_NAME" ]; then UNINSTALLER="$p"; fi
  done < <(cat "$WORK/apps"; [ -d "$SCRIPT_DIR/$APP_NAME" ] && echo "$SCRIPT_DIR/$APP_NAME")

  if [ -n "$UNINSTALLER" ]; then
    if [ "$UNINSTALLER" != "/Applications/$APP_NAME" ]; then
      say "  macOS dezactivează extensia doar prin aplicația din Aplicații — copiez $(app_version "$UNINSTALLER") acolo"
      run_root rm -rf "/Applications/$APP_NAME"
      run_root /usr/bin/ditto "$UNINSTALLER" "/Applications/$APP_NAME"
    fi
    if [ "$DRY" = 1 ]; then
      say "  [dry-run] \"/Applications/$APP_NAME/Contents/MacOS/GDC Firewall\" --uninstall-extension"
    else
      "/Applications/$APP_NAME/Contents/MacOS/GDC Firewall" --uninstall-extension
      rc=$?
      [ "$rc" = 1 ] && FAILED=1
    fi
  elif grep -q "disabled" < <(csrutil status 2>/dev/null); then
    say "  Nicio copie nouă a aplicației; SIP e dezactivat → systemextensionsctl"
    run_root systemextensionsctl uninstall "$TEAM_ID" "$EXT_ID" || FAILED=1
  else
    say "  ✗ Nu am găsit o copie GDC Firewall $MIN_UNINSTALL+ care să dezactiveze extensia."
    say "    Descarcă ultima versiune de pe https://gordas.dev/gdc-firewall, dezarhiveaz-o"
    say "    și rulează dezinstalatorul din arhiva nouă (îl folosește automat)."
    FAILED=1
  fi
else
  say "  — extensia nu e activă, nicio configurație de filtru"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "3. Fișierele"
find_apps > "$WORK/apps"   # include copia pusă mai sus în /Applications
while IFS= read -r p; do
  if [ "$DRY" = 1 ]; then say "  [dry-run] șterg $p"; continue; fi
  sudo rm -rf "$p" && say "  ✓ $p" || { say "  ✗ $p"; FAILED=1; }
done < <(cat "$WORK/apps"; existing_files)
if [ "$DRY" = 0 ]; then
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1
  tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Verificare"
[ "$DRY" = 1 ] && { say "Previzualizare încheiată. Rulează fără --dry-run pentru dezinstalare."; exit 0; }
LEFT=0
REMAINING="$( { find_apps; existing_files; } | sort -u)"
if [ -z "$REMAINING" ]; then say "✓ Nicio copie a aplicației, niciun fișier rămas"; else say "✗ Rămase:"; say "$REMAINING" | sed 's/^/  /'; LEFT=1; fi
if [ "$(ext_active)" -gt 0 ]; then
  say "✗ Extensia de rețea e încă activă → Setări de sistem → General → Elemente de login și extensii → Extensii de rețea"; LEFT=1
elif [ -n "$(ext_states)" ]; then
  say "✓ Extensia de rețea e dezactivată; macOS o șterge definitiv la următoarea repornire"
else
  say "✓ Extensia de rețea nu mai există"
fi
if [ "$(ne_config)" -gt 0 ]; then
  say "✗ Filtrul „GDC Firewall” apare încă în Setări de sistem → Rețea → Filtre — îl poți șterge de acolo"; LEFT=1
else
  say "✓ Nicio configurație de filtru rămasă"
fi
echo
if [ "$LEFT" = 0 ] && [ "$FAILED" = 0 ]; then
  echo "✅ GDC Firewall a fost dezinstalat complet."
else
  echo "⚠️  Dezinstalare încheiată cu elementele de mai sus de rezolvat."
fi
echo "   LuLu sau Little Snitch, dacă sunt instalate separat, au rămas neatinse."
read -n 1 -s -r -p "Apasă orice tastă pentru a închide." </dev/tty 2>/dev/null
echo
