#!/bin/bash
# Testul de integrare al gărzii de actualizare (2.3.5), pe Mac-ul real.
# Nu modifică nimic în motor sau în reguli: doar citește și compară.
#
#   ./scripts/verify-update-guard.sh before   ÎNAINTE de instalarea versiunii noi:
#                                             salvează regulile și starea curentă
#   ./scripts/verify-update-guard.sh after    DUPĂ instalare + aprobare: verifică
#                                             garda ridicată, modul normal, regulile
#   ./scripts/verify-update-guard.sh probe    un binar NOU, fără regulă, face o
#                                             conexiune: trebuie să apară o alertă,
#                                             nu blocare tăcută (-1005). Ieșire 3 = blocată
#                                             de o regulă explicită (nu e defect al gărzii)
#   ./scripts/verify-update-guard.sh rules-check [binar]   doar citește regulile
#
# Starea salvată: ~/Library/Caches/GDCFirewall-guardtest/
set -uo pipefail

DIR="$HOME/Library/Caches/GDCFirewall-guardtest"
DATA="/Library/Application Support/GDC Firewall"
# GDCFW_PREFS / GDCFW_RULES: doar pentru testarea scriptului pe copii.
PREFS="${GDCFW_PREFS:-$DATA/preferences.plist}"
RULES="${GDCFW_RULES:-$DATA/rules.plist}"
APP="/Applications/GDC Firewall.app"
APP_EXT="$APP/Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension/Contents/Info.plist"
LOG="$HOME/Library/Logs/GDCFirewall.log"
mkdir -p "$DIR"

ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; FAIL=1; }
FAIL=0

# Regulile, ca listă „cheie<TAB>număr de reguli” (arhiva NSKeyedArchiver a motorului).
rules_summary() {
  python3 - "$RULES" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    p = plistlib.load(f)
objs = p["$objects"]
def res(u): return objs[u.data] if isinstance(u, plistlib.UID) else u
root = res(p["$top"]["root"])
keys = [res(k) for k in root.get("NS.keys", [])]
vals = [res(v) for v in root.get("NS.objects", [])]
for k, v in sorted(zip(keys, vals), key=lambda x: str(x[0])):
    n = len(v.get("NS.objects", [])) if isinstance(v, dict) else 1
    print(f"{k}\t{n}")
PY
}

# Reguli ACTIVE de blocare care se aplică binarului $1 spre $2 (orice proces „*” sau binarul însuși).
# O blocare prin regulă explicită e o decizie a utilizatorului, nu o defecțiune a gărzii.
blocking_rules() {
  python3 - "$RULES" "$1" "$2" <<'PY'
import plistlib, re, sys, os
rules, binpath, host = sys.argv[1:4]
p = plistlib.load(open(rules, "rb")); o = p["$objects"]
def R(x):
    while isinstance(x, plistlib.UID): x = o[x.data]
    if isinstance(x, dict) and "NS.keys" in x: return {str(R(k)): R(v) for k, v in zip(x["NS.keys"], x["NS.objects"])}
    if isinstance(x, dict) and "NS.objects" in x: return [R(v) for v in x["NS.objects"]]
    if isinstance(x, dict): return {k: R(v) for k, v in x.items() if k != "$class"}
    return x
root = R(p["$top"]["root"])
keys = {"*", binpath, os.path.basename(binpath)}
for key, entry in root.items():
    if key not in keys: continue
    for r in entry.get("rules", []):
        disabled = r.get("isDisabled") not in (None, "$null", 0, False)
        if r.get("action") != 0 or disabled: continue
        addr, port = str(r.get("endpointAddr")), str(r.get("endpointPort"))
        if port not in ("*", "443"): continue
        if addr == "*" or (r.get("isEndpointAddrRegex") and re.search(addr, host)) or addr == host:
            print(f"{key} → {addr}:{port} (uuid {r.get('uuid')})")
PY
}

passive() { plutil -p "$PREFS" 2>/dev/null | grep -E '"passiveMode(Action|Rules)?"' | tr -s ' '; }
labels()  { grep -oE 'NetworkExtension\.dev\.gordas\.GDCFirewall\.extension\.[0-9.]+' < <(launchctl print system 2>/dev/null) | sort -u; }
bundled() {
  [ -f "$APP_EXT" ] || return
  echo "NetworkExtension.dev.gordas.GDCFirewall.extension.$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_EXT").$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_EXT")"
}

case "${1:-}" in
before)
  rules_summary > "$DIR/rules-before.tsv" || { echo "‼️  Nu pot citi $RULES"; exit 1; }
  passive > "$DIR/passive-before.txt"
  wc -l < "$LOG" | tr -d ' ' > "$DIR/log-offset.txt" 2>/dev/null || echo 0 > "$DIR/log-offset.txt"
  echo "Salvat în $DIR:"
  echo "  reguli: $(wc -l < "$DIR/rules-before.tsv" | tr -d ' ') aplicații, $(awk -F'\t' '{s+=$2} END {print s+0}' "$DIR/rules-before.tsv") reguli"
  echo "  mod pasiv acum:"; sed 's/^/    /' "$DIR/passive-before.txt"
  echo "  aplicația: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '—')"
  echo "  extensii în launchd:"; labels | sed 's/^/    /'
  ;;
after)
  [ -f "$DIR/rules-before.tsv" ] || { echo "‼️  Rulează întâi: $0 before"; exit 1; }
  echo "1. Versiuni"
  V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
  [ "$V" = "2.3.5" ] && ok "aplicația din /Applications: $V" || bad "aplicația din /Applications: ${V:-lipsă} (aștept 2.3.5)"
  B="$(bundled)"; L="$(labels)"
  if [ -n "$B" ] && [ "$L" = "$B" ]; then ok "rulează doar extensia din pachet: $B"
  else bad "extensii în launchd: ${L:-niciuna} (aștept doar ${B:-?})"; fi

  echo "2. Modul pasiv al motorului (preferences.plist)"
  P="$(passive)"; echo "$P" | sed 's/^/    /'
  grep -q '"passiveMode" => false' <<< "$P" || [ -z "$(grep '"passiveMode"' <<< "$P")" ] \
    && ok "passiveMode = false (fără blocare tăcută)" || bad "passiveMode e încă true"

  echo "3. Garda în evidența aplicației (UserDefaults)"
  if defaults read dev.gordas.GDCFirewall 2>/dev/null | grep -q "updateGuard"; then
    bad "cheile gărzii există încă:"; defaults read dev.gordas.GDCFirewall | grep -A4 updateGuard | sed 's/^/    /'
  else ok "nicio cheie GDCFirewall.updateGuard.* — garda ridicată și confirmată"; fi

  echo "4. Regulile utilizatorului"
  rules_summary > "$DIR/rules-after.tsv"
  MISSING="$(python3 - "$DIR/rules-before.tsv" "$DIR/rules-after.tsv" <<'PY'
import sys
def load(p): return dict(l.rstrip("\n").split("\t", 1) for l in open(p) if "\t" in l)
b, a = load(sys.argv[1]), load(sys.argv[2])
for k, n in b.items():
    if k not in a: print(f"LIPSEȘTE: {k} ({n} reguli)")
    elif int(a[k]) < int(n): print(f"MAI PUȚINE: {k} {n} → {a[k]}")
new = [k for k in a if k not in b]
print(f"#noi {len(new)}")
PY
)"
  NEW="$(grep '^#noi' <<< "$MISSING" | cut -d' ' -f2)"; MISSING="$(grep -v '^#noi' <<< "$MISSING")"
  if [ -z "$MISSING" ]; then ok "toate regulile de dinainte există ($(wc -l < "$DIR/rules-before.tsv" | tr -d ' ') aplicații); aplicații noi: $NEW"
  else bad "reguli pierdute:"; echo "$MISSING" | sed 's/^/    /'; fi

  echo "5. Jurnalul aplicației (de la 'before')"
  OFF="$(cat "$DIR/log-offset.txt" 2>/dev/null || echo 0)"
  tail -n +"$((OFF + 1))" "$LOG" 2>/dev/null | grep -E "updateguard|Etapă actualizare|Rulează altă versiune|confirmat" | tail -20 | sed 's/^/    /'
  tail -n +"$((OFF + 1))" "$LOG" 2>/dev/null | grep -q "Garda de actualizare ridicată" \
    && ok "logul confirmă ridicarea gărzii" || echo "  ℹ fără linia „Garda de actualizare ridicată” (normal dacă garda n-a fost pusă — vezi rândul „Modul normal refăcut”)"
  echo
  [ "$FAIL" -eq 0 ] && echo "✅ Garda de actualizare: TOTUL OK" || { echo "❌ Au apărut probleme (vezi ✗)."; exit 1; }
  ;;
probe)
  # Binar nou la fiecare rulare → nicio regulă existentă pentru el.
  STAMP="$(date +%Y%m%d-%H%M%S)"; SRC="$DIR/probe.swift"; BIN="$DIR/gdc-probe-$STAMP"
  cat > "$SRC" <<'SWIFT'
import Foundation
let url = URL(string: "https://gordas.dev/gdc-firewall/update.json")!
let cfg = URLSessionConfiguration.ephemeral; cfg.timeoutIntervalForRequest = 90
let sem = DispatchSemaphore(value: 0); let t0 = Date()
URLSession(configuration: cfg).dataTask(with: url) { _, resp, err in
    let s = String(format: "%.1f", Date().timeIntervalSince(t0))
    if let err = err as NSError? { print("EROARE \(err.code) după \(s) s: \(err.localizedDescription)") }
    else { print("OK HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0) după \(s) s") }
    sem.signal()
}.resume()
sem.wait()
SWIFT
  swiftc -O "$SRC" -o "$BIN" 2>/dev/null || { echo "‼️  swiftc a eșuat"; exit 1; }
  echo "Sondă: $BIN"
  echo "→ Acum trebuie să apară alerta GDC Firewall pentru „$(basename "$BIN")”. Alege „Permite”."
  OUT="$("$BIN")"; echo "  $OUT"
  case "$OUT" in
    "OK HTTP"*) ok "conexiunea a trecut după alertă — aplicațiile noi nu mai sunt blocate tăcut" ;;
    *"-1005"*|*"-1009"*)
      if grep -q '"passiveMode" => true' <<< "$(passive)"; then
        bad "blocare tăcută: modul pasiv e activ (garda sau o setare rămasă) — vezi „after”"
      elif BR="$(blocking_rules "$BIN" "gordas.dev")" && [ -n "$BR" ]; then
        echo "  ℹ blocată de o regulă EXPLICITĂ a utilizatorului, nu de gardă:"; echo "$BR" | sed 's/^/      /'
        echo "    Testul de alertă nu se poate face cât regula e activă (o dezactivezi din fereastra Reguli)."
        exit 3
      else
        bad "blocare fără alertă, fără mod pasiv și fără regulă de blocare potrivită — trimite ./scripts/logs.sh 10"
      fi ;;
    *) echo "  ℹ rezultat neclar: dacă ai ales „Blochează”, e normal; altfel trimite ieșirea de mai sus" ;;
  esac
  echo "  (Regula nouă creată pentru sondă se poate șterge din Reguli; binarul: rm \"$BIN\")"
  [ "$FAIL" -eq 0 ] || exit 1
  ;;
rules-check)
  # Ce reguli active ar bloca un binar nou („*”) sau binarul dat, spre gordas.dev.
  BR="$(blocking_rules "${2:-/nonexistent/gdc-probe-nou}" "gordas.dev")"
  [ -n "$BR" ] && { echo "Reguli de blocare aplicabile:"; echo "$BR" | sed 's/^/  /'; exit 3; }
  echo "Nicio regulă activă nu blochează un binar nou spre gordas.dev." ;;
*)
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
