#!/bin/bash
# Dezinstalare completă Little Snitch + LuLu (de ex. înainte de GDC Firewall).
# Versiune 1.0.0 · gordas.dev · instrucțiuni: Dezinstalare_LittleSnitch_LuLu.md
#
#   dublu-click, sau în Terminal:  bash Dezinstalare_LittleSnitch_LuLu.command
#   … --dry-run                    # doar inventarul și planul; nu modifică nimic
#   … --dry-run --assume-sip-on    # planul pentru un Mac cu SIP activ (cazul obișnuit)
#   … --yes                        # fără confirmare
#
# Siguranță, intenționat:
#   - Nimic nu se șterge definitiv: totul se MUTĂ în Coș, într-un folder datat,
#     cu calea originală păstrată. Golești Coșul când ești sigur.
#   - GDC Firewall (dev.gordas.GDCFirewall, „GDC Firewall”) e exclus din orice
#     acțiune; verificarea finală confirmă că a rămas neatins.
#   - Doar subfolderele Little Snitch / LuLu. „Objective-See” (BlockBlock) și
#     „Objective Development” rămân; se elimină doar dacă ajung goale.
#   - Procesele se opresc după calea executabilului, niciodată după textul din
#     linia de comandă (pkill -f): PATH-ul unor procese fără legătură conține
#     „Little Snitch.app”.
#   - /Library/SystemExtensions e protejat de SIP: extensiile se dezinstalează
#     prin systemextensionsctl (SIP dezactivat) sau prin Finder (SIP activ).
#   - com.apple.networkextension.plist (filtrele macOS) e comun cu GDC Firewall:
#     doar raportat, niciodată editat.
#   Log: ~/Library/Logs/GDCFirewall-cleanup.log
set -uo pipefail

DRY=0
YES=0
ASSUME_SIP_ON=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY=1 ;;
    -y|--yes) YES=1 ;;
    --assume-sip-on) ASSUME_SIP_ON=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opțiune necunoscută: $arg (vezi --help)" >&2; exit 2 ;;
  esac
done

if [ "$ASSUME_SIP_ON" = 1 ] && [ "$DRY" = 0 ]; then
  echo "--assume-sip-on e doar pentru previzualizare (--dry-run)." >&2; exit 2
fi

# --- Utilizatorul real (căile ~ ale lui, nu ale lui root) -------------------
if [ "$(id -u)" = 0 ]; then
  TUSER="${SUDO_USER:-}"
  if [ -z "$TUSER" ] || [ "$TUSER" = root ]; then TUSER="$(stat -f %Su /dev/console)"; fi
else
  if [ "$DRY" = 0 ]; then
    # Dublu-click: scriptul rulează ca utilizator; componentele de sistem cer root.
    echo "Curățarea atinge fișiere de sistem, deci macOS îți cere parola de administrator"
    echo "a Mac-ului (nu se vede nimic cât o tastezi — apasă Enter la final)."
    exec sudo /bin/bash "$0" "$@"
  fi
  TUSER="$(id -un)"
fi

if [ -z "$TUSER" ] || [ "$TUSER" = root ]; then
  echo "Nu pot determina utilizatorul. Rulează cu sudo din contul tău." >&2
  exit 1
fi
TUID="$(id -u "$TUSER")"
H="$(dscl . -read "/Users/$TUSER" NFSHomeDirectory | awk '{print $2}')"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG="$H/Library/Logs/GDCFirewall-cleanup.log"
WORK="$(mktemp -d)"

if [ "$DRY" = 0 ]; then
  touch "$LOG" && chown "$TUSER" "$LOG"
fi
pause_if_interactive() {
  if [ -t 0 ] && [ "$YES" = 0 ]; then read -n 1 -s -r -p "Apasă orice tastă pentru a închide." </dev/tty; echo; fi
}
trap 'rm -rf "$WORK"; pause_if_interactive' EXIT
out() {  # nivel mesaj — consolă + log (Regula 39)
  echo "$2"
  if [ "$DRY" = 0 ]; then
    printf '%s %-5s [cleanup] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" "$2" >> "$LOG"
  fi
}

# --- Garda: ce nu se atinge niciodată ---------------------------------------
protected() {
  case "$1" in
    *"GDC Firewall"*|*GDCFirewall*|*gdc-firewall*|*dev.gordas*|*com.gordas*) return 0 ;;
    "$H/Developer"|"$H/Developer/"*) return 0 ;;
    */BlockBlock*|*/Objective-See|*/"Objective Development") return 0 ;;
  esac
  return 1
}

# --- Inventar ----------------------------------------------------------------
SCAN_DIRS=(
  /Applications "$H/Applications" /Library
  /Library/LaunchDaemons /Library/LaunchAgents "$H/Library/LaunchAgents"
  "/Library/Application Support" "/Library/Application Support/Objective Development"
  "/Library/Application Support/Objective-See" /Library/Objective-See
  "$H/Library/Application Support" "$H/Library/Application Support/Objective Development"
  "$H/Library/Application Support/CrashReporter"
  /Library/Preferences "$H/Library/Preferences" "$H/Library/Preferences/ByHost"
  /Library/Extensions /Library/PrivilegedHelperTools
  /Library/Logs /Library/Logs/DiagnosticReports "$H/Library/Logs" "$H/Library/Logs/DiagnosticReports"
  /Library/Caches "$H/Library/Caches" "$H/Library/HTTPStorages" "$H/Library/WebKit"
  "$H/Library/Containers" "$H/Library/Group Containers" "$H/Library/Saved Application State"
  "$H/Library/Application Scripts" /private/etc/paths.d /usr/local/bin
  /private/var/root/Library/Preferences /private/var/root/Library/Caches
  "/private/var/root/Library/Application Support" /private/var/root/Library/Logs
)

# Adâncime 1 pe fiecare folder (subfolderele relevante sunt listate explicit):
# o căutare recursivă în ~/Library ar atinge containerele altor aplicații.
scan_files() {
  local d
  for d in "${SCAN_DIRS[@]}"; do
    [ -d "$d" ] || continue
    find "$d" -mindepth 1 -maxdepth 1 \( -iname '*littlesnitch*' -o -iname '*little snitch*' \
      -o -iname '*objective-see.lulu*' -o -name '*LuLu*' \) 2>/dev/null
  done | sort -u
}

# echipă<TAB>bundle<TAB>stare
scan_sysext() {
  systemextensionsctl list 2>/dev/null | awk -F'\t' '
    $4 ~ /^(at\.obdev\.littlesnitch|com\.objective-see\.lulu)/ { b = $4; sub(/ \(.*/, "", b); print $3 "\t" b "\t" $6 }' | sort -u
}

# domeniu<TAB>etichetă — doar joburile proprii; cele ale extensiilor de sistem
# (prefix NetworkExtension. / Team ID) dispar odată cu extensiile.
scan_jobs() {
  local dom
  for dom in system "gui/$TUID"; do
    launchctl print "$dom" 2>/dev/null | awk -F'\t' -v d="$dom" '
      NF >= 4 && $NF ~ /^(at\.obdev\.littlesnitch|com\.objective-see\.lulu)/ { print d "\t" $NF }'
  done | sort -u
}

# pid<TAB>executabil — după calea executabilului, nu după argumente.
scan_procs() {
  local pid comm
  ps -axo pid=,comm= | while read -r pid comm; do
    case "$comm" in
      "/Applications/Little Snitch.app/"*|"$H/Applications/Little Snitch.app/"*|\
      "/Library/Application Support/Objective Development/Little Snitch/"*|"/Library/Little Snitch/"*|\
      "/Applications/LuLu.app/"*|"$H/Applications/LuLu.app/"*|"/Library/Objective-See/LuLu/"*)
        printf '%s\t%s\n' "$pid" "$comm" ;;
    esac
  done
}

scan_pkgs() {
  grep -iE '^(at\.obdev\.littlesnitch|com\.objective-see\.lulu)' < <(pkgutil --pkgs 2>/dev/null)
}

# Filtrele rămase în configurația NetworkExtension a macOS (doar citire).
scan_ne_config() {
  local f=/Library/Preferences/com.apple.networkextension.plist
  [ -r "$f" ] || return 0
  grep -oE '"(at\.obdev\.littlesnitch|com\.objective-see\.lulu)[A-Za-z0-9._-]*"' < <(plutil -p "$f" 2>/dev/null) | tr -d '"' | sort -u
}

gdc_fingerprint() {
  local p
  for p in "/Applications/GDC Firewall.app" "/Library/Application Support/GDC Firewall" \
           "$H/Library/Application Support/GDCFirewall" "$H/Library/Preferences/dev.gordas.GDCFirewall.plist"; do
    if [ -e "$p" ]; then echo "$(stat -f %i "$p") $p"; else echo "absent $p"; fi
  done
  systemextensionsctl list 2>/dev/null | awk -F'\t' '$4 ~ /^dev\.gordas\.GDCFirewall\.extension/ && $6 ~ /activated enabled/ { print "extensie " $4 " " $6 }'
}

split_protected() {  # fișier-intrare → $1.act (de curățat), $1.prot (protejate)
  : > "$1.act"; : > "$1.prot"
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if protected "$p"; then echo "$p" >> "$1.prot"; else echo "$p" >> "$1.act"; fi
  done < "$1"
}

count() { grep -c . "$1" 2>/dev/null || true; }

list_block() {  # titlu fișier [prefix]
  local n; n="$(count "$2")"
  out INFO "$1 ($n):"
  [ "$n" = 0 ] && { out INFO "  —"; return; }
  while IFS= read -r line; do out INFO "  • ${line//$'\t'/  }"; done < "$2"
}

inventory() {  # prefix de fișiere
  scan_files > "$1.files";   split_protected "$1.files"
  scan_jobs > "$1.jobs"
  scan_procs > "$1.procs"
  scan_sysext > "$1.sysext"
  scan_pkgs > "$1.pkgs"
  scan_ne_config > "$1.ne"
}

# --- 1. Inventar + previzualizare ---------------------------------------------
gdc_fingerprint > "$WORK/gdc.before"
inventory "$WORK/pre"

out INFO "=== Little Snitch / LuLu — inventar ($(date '+%Y-%m-%d %H:%M'), utilizator $TUSER) ==="
[ "$(id -u)" = 0 ] || out INFO "(fără root: /private/var/root nu poate fi citit — inventarul complet apare la rularea cu sudo)"
list_block "Fișiere și foldere de mutat la Coș" "$WORK/pre.files.act"
list_block "Joburi launchd de oprit (bootout)" "$WORK/pre.jobs"
list_block "Procese de oprit" "$WORK/pre.procs"
list_block "Extensii de sistem (echipă, bundle, stare)" "$WORK/pre.sysext"
list_block "Chitanțe de instalare (pkgutil --forget)" "$WORK/pre.pkgs"
list_block "Filtre în configurația macOS (doar raportate)" "$WORK/pre.ne"
if [ "$(count "$WORK/pre.files.prot")" != 0 ]; then
  list_block "PROTEJATE — nu se ating" "$WORK/pre.files.prot"
fi

TOTAL=$(( $(count "$WORK/pre.files.act") + $(count "$WORK/pre.jobs") + $(count "$WORK/pre.procs") \
        + $(count "$WORK/pre.sysext") + $(count "$WORK/pre.pkgs") ))
if [ "$TOTAL" = 0 ]; then
  out INFO "✓ Nimic de curățat: nicio urmă Little Snitch / LuLu."
  exit 0
fi
SIP_OFF=0
grep -q "disabled" < <(csrutil status 2>/dev/null) && SIP_OFF=1
[ "$ASSUME_SIP_ON" = 1 ] && SIP_OFF=0
if [ "$DRY" = 1 ]; then
  out INFO "=== Plan (SIP $([ "$SIP_OFF" = 1 ] && echo dezactivat || echo "ACTIV — cazul obișnuit")) ==="
  if [ "$SIP_OFF" = 1 ]; then
    out INFO "  1. extensiile de mai sus: systemextensionsctl uninstall (posibil doar cu SIP dezactivat)"
  else
    out INFO "  1. extensiile se scot prin mecanismul macOS: aplicația mutată la Coș prin Finder"
    for app in "/Applications/Little Snitch.app" "/Applications/LuLu.app"; do
      [ -d "$app" ] && out INFO "     • $app → la Coș prin Finder (macOS poate cere parola)"
    done
    out INFO "     • extensiile active fără aplicație: pași manuali în Setări de sistem (îi arată verificarea)"
  fi
  out INFO "  2. joburile launchd de mai sus: launchctl bootout"
  out INFO "  3. procesele rămase: oprite după calea executabilului"
  out INFO "  4. fișierele de mai sus: mutate la Coș, în „Firewall-uri eliminate <data>”"
  out INFO "  5. verificare finală + confirmarea că GDC Firewall a rămas neatins"
  out INFO "Previzualizare: nimic nu a fost modificat."
  exit 0
fi

if [ "$YES" = 0 ]; then
  printf '\nMut elementele de mai sus la Coș și opresc componentele. Scrie „da” pentru a continua: '
  read -r answer
  if [ "$(tr '[:upper:]' '[:lower:]' <<< "$answer")" != "da" ]; then
    out INFO "Anulat de utilizator. Nimic nu a fost modificat."
    exit 0
  fi
fi

DEST="$H/.Trash/Firewall-uri eliminate $STAMP"
if ! mkdir -p "$DEST" 2>/dev/null; then
  DEST="$H/Firewall-uri eliminate $STAMP"   # Coșul poate fi blocat de TCC fără Full Disk Access
  mkdir -p "$DEST" || { out ERROR "Nu pot crea $DEST"; exit 1; }
fi
chown "$TUSER" "$DEST"
out INFO "Destinație: $DEST"
MOVED=0
FAILED=0

move_away() {
  local src="$1"
  if protected "$src"; then out WARN "  PROTEJAT, neatins: $src"; return; fi
  [ -e "$src" ] || [ -L "$src" ] || return 0
  mkdir -p "$DEST$(dirname "$src")"
  if mv "$src" "$DEST$src" 2>"$WORK/mv.err"; then
    out INFO "  ✓ mutat: $src"; MOVED=$((MOVED + 1))
  else
    out ERROR "  ✗ NU s-a putut muta: $src ($(tr '\n' ' ' < "$WORK/mv.err"))"; FAILED=$((FAILED + 1))
  fi
}

# --- 2. Extensii de sistem ----------------------------------------------------
out INFO "--- Extensii de sistem (SIP $([ "$SIP_OFF" = 1 ] && echo dezactivat || echo activ)) ---"
while IFS=$'\t' read -r team bundle state; do
  [ -n "$bundle" ] || continue
  case "$state" in *terminated*|*uninstalling*) out INFO "  $bundle: deja în curs de eliminare ($state)"; continue ;; esac
  if [ "$SIP_OFF" = 1 ]; then
    if systemextensionsctl uninstall "$team" "$bundle" > "$WORK/sx.out" 2>&1; then
      out INFO "  ✓ dezinstalată: $bundle ($team)"
    else
      out ERROR "  ✗ $bundle: $(tr '\n' ' ' < "$WORK/sx.out")"; FAILED=$((FAILED + 1))
    fi
  else
    case "$bundle" in at.obdev.*) owner="/Applications/Little Snitch.app" ;; *) owner="/Applications/LuLu.app" ;; esac
    if [ -d "$owner" ]; then
      out INFO "  $bundle: se elimină prin Finder, odată cu ${owner##*/} (SIP activ)"
    else
      out WARN "  $bundle: fără ${owner##*/} — pașii manuali apar la verificare (SIP activ)"
    fi
  fi
done < "$WORK/pre.sysext"

# Cu SIP activ, singura cale acceptată de macOS: aplicația mutată la Coș din
# Finder, care declanșează dezinstalarea extensiilor ei (cu promptul nativ).
if [ "$SIP_OFF" = 0 ]; then
  for app in "/Applications/Little Snitch.app" "/Applications/LuLu.app"; do
    [ -d "$app" ] || continue
    if launchctl asuser "$TUID" sudo -u "$TUSER" /usr/bin/osascript \
         -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' -e 'end run' \
         "$app" >/dev/null 2>&1; then
      out INFO "  ✓ $app mutat la Coș prin Finder (macOS îi dezinstalează extensiile)"
    else
      out WARN "  $app: Finder a refuzat; îl mut direct, extensiile rămân de scos manual (vezi verificarea)"
    fi
  done
fi

# --- 3. Joburi launchd ----------------------------------------------------------
out INFO "--- Joburi launchd ---"
{
  cat "$WORK/pre.jobs"
  while IFS= read -r plist; do
    case "$plist" in
      /Library/LaunchDaemons/*.plist) dom=system ;;
      /Library/LaunchAgents/*.plist|"$H/Library/LaunchAgents/"*.plist) dom="gui/$TUID" ;;
      *) continue ;;
    esac
    label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null)" || continue
    printf '%s\t%s\n' "$dom" "$label"
  done < "$WORK/pre.files.act"
} | sort -u > "$WORK/jobs.all"
while IFS=$'\t' read -r dom label; do
  [ -n "$label" ] || continue
  if launchctl bootout "$dom/$label" > "$WORK/bo.out" 2>&1; then
    out INFO "  ✓ oprit: $dom/$label"
  else
    out INFO "  $dom/$label: nu era încărcat ($(tr '\n' ' ' < "$WORK/bo.out"))"
  fi
done < "$WORK/jobs.all"

# --- 4. Procese rămase ------------------------------------------------------------
out INFO "--- Procese ---"
scan_procs > "$WORK/procs.now"
while IFS=$'\t' read -r pid comm; do
  [ -n "$pid" ] || continue
  kill -TERM "$pid" 2>/dev/null && out INFO "  SIGTERM $pid $comm"
done < "$WORK/procs.now"
sleep 3
scan_procs > "$WORK/procs.left"
while IFS=$'\t' read -r pid comm; do
  [ -n "$pid" ] || continue
  kill -KILL "$pid" 2>/dev/null && out INFO "  SIGKILL $pid $comm"
done < "$WORK/procs.left"
[ "$(count "$WORK/procs.now")" = 0 ] && out INFO "  — niciun proces activ"

# --- 5. Fișiere (inventar refăcut: Finder poate fi mutat deja aplicațiile) --------
out INFO "--- Fișiere și foldere ---"
scan_files > "$WORK/files.now"
split_protected "$WORK/files.now"
while IFS= read -r p; do move_away "$p"; done < "$WORK/files.now.act"

# --- 6. Chitanțe pkg + foldere-părinte rămase goale --------------------------------
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  pkgutil --forget "$pkg" >/dev/null 2>&1 && out INFO "  ✓ chitanță eliminată: $pkg"
done < "$WORK/pre.pkgs"
for d in "/Library/Application Support/Objective Development" "$H/Library/Application Support/Objective Development" \
         "/Library/Objective-See" "/Library/Application Support/Objective-See"; do
  [ -d "$d" ] || continue
  rm -f "$d/.DS_Store" 2>/dev/null
  rmdir "$d" 2>/dev/null && out INFO "  ✓ folder gol eliminat: $d"
done

# --- 7. Verificare finală ------------------------------------------------------------
out INFO "=== Verificare ==="
inventory "$WORK/post"
LEFT=0
if [ "$(count "$WORK/post.files.act")" = 0 ]; then
  out INFO "✓ Fișiere: nicio urmă rămasă"
else
  list_block "✗ Fișiere rămase" "$WORK/post.files.act"; LEFT=1
fi
[ "$(count "$WORK/post.jobs")" = 0 ] && out INFO "✓ launchd: niciun job" || { list_block "✗ Joburi rămase" "$WORK/post.jobs"; LEFT=1; }
[ "$(count "$WORK/post.procs")" = 0 ] && out INFO "✓ Procese: niciunul" || { list_block "✗ Procese rămase" "$WORK/post.procs"; LEFT=1; }
[ "$(count "$WORK/post.pkgs")" = 0 ] || { list_block "✗ Chitanțe rămase" "$WORK/post.pkgs"; LEFT=1; }

ACTIVE_SX="$(grep -vE 'terminated|uninstalling' "$WORK/post.sysext" || true)"
if [ -n "$ACTIVE_SX" ]; then
  LEFT=1
  out WARN "✗ Extensii de sistem încă active:"
  while IFS= read -r l; do out WARN "  • ${l//$'\t'/  }"; done <<< "$ACTIVE_SX"
  out WARN "  → Setări de sistem → General → Elemente de login și extensii → Extensii: dezactivează-le;"
  out WARN "    sau reinstalează aplicația respectivă și folosește dezinstalarea ei."
elif [ "$(count "$WORK/post.sysext")" != 0 ]; then
  out INFO "✓ Extensii de sistem: dezinstalate — dispar definitiv după următoarea repornire"
else
  out INFO "✓ Extensii de sistem: niciuna"
fi
if [ "$(count "$WORK/post.ne")" != 0 ]; then
  list_block "ℹ Filtre rămase în Setări de sistem → Rețea → Filtre (inactive fără extensie; le poți elimina de acolo)" "$WORK/post.ne"
fi

gdc_fingerprint > "$WORK/gdc.after"
if ! grep -qv "^absent " "$WORK/gdc.before"; then
  out INFO "ℹ GDC Firewall nu e instalat pe acest Mac — nimic de protejat"
elif cmp -s "$WORK/gdc.before" "$WORK/gdc.after"; then
  out INFO "✓ GDC Firewall neatins ($(grep -c . "$WORK/gdc.after") repere identice înainte/după)"
else
  out ERROR "‼️ GDC Firewall s-a schimbat în timpul curățării:"
  while IFS= read -r l; do out ERROR "  $l"; done < <(diff "$WORK/gdc.before" "$WORK/gdc.after")
  LEFT=1
fi

out INFO "Rezumat: $MOVED mutate, $FAILED eșuate. Elementele sunt în: $DEST"
out INFO "Log complet: $LOG"
[ "$LEFT" = 0 ] && [ "$FAILED" = 0 ] && exit 0
exit 1
