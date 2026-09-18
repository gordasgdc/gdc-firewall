#!/bin/bash
# Starea GDC Firewall pe stația de dezvoltare (Regula 39), într-un singur loc:
# procese, extensie, fișierul de log al aplicației și unified log-ul extensiei
# (motorul LuLu scrie sub subsistemul com.objective-see.lulu).
#
# Utilizare:
#   scripts/logs.sh            instantaneu: stare + ultimele evenimente (15 min)
#   scripts/logs.sh 60         la fel, pe ultimele 60 de minute
#   scripts/logs.sh --follow   urmărire live: fișierul aplicației + motorul
set -uo pipefail

LOG_FILE="$HOME/Library/Logs/GDCFirewall.log"
APP_ID="dev.gordas.GDCFirewall"
EXT_ID="${APP_ID}.extension"
ENGINE="process == \"${EXT_ID}\" AND (subsystem == \"com.objective-see.lulu\" OR messageType == error)"
# Zgomot de sistem din procesul extensiei, fără legătură cu filtrarea.
NOISE='TemporalValidity|SecError|libsqlite3|DetachedSignatures|No current verdict available|LegacyAPICounts'

if [ "${1:-}" = "--follow" ]; then
  echo "→ Urmăresc ${LOG_FILE} și motorul de filtrare (Ctrl+C pentru oprire)…"
  touch "$LOG_FILE"
  # Aplicația scrie deja tot în fișier; din unified log vine doar motorul.
  tail -n 0 -F "$LOG_FILE" &
  TAIL_PID=$!
  trap 'kill $TAIL_PID 2>/dev/null' EXIT
  /usr/bin/log stream --style compact --level info --predicate "$ENGINE" | grep --line-buffered -vE "$NOISE"
  exit 0
fi

MINUTES="${1:-15}"

echo "=== Procese"
pgrep -lf "GDC Firewall.app/Contents/MacOS" | sed 's/^/  aplicație: /' || echo "  aplicația NU rulează"
pgrep -f "${EXT_ID}.systemextension" | sed 's/^/  extensie: pid /' || echo "  extensia NU rulează"

echo "=== Extensie (systemextensionsctl)"
systemextensionsctl list 2>/dev/null | grep "$EXT_ID" | sed -E 's/^[[:space:]*]+/  /' || echo "  neinstalată"

echo "=== ${LOG_FILE} — ultimele 40 de linii"
if [ -f "$LOG_FILE" ]; then
  tail -n 40 "$LOG_FILE" | sed 's/^/  /'
else
  echo "  nu există încă (se creează la prima pornire a unei versiuni ≥ 2.2.1)"
fi

echo "=== Motor de filtrare, unified log — ultimele ${MINUTES} min"
/usr/bin/log show --last "${MINUTES}m" --style compact --predicate "$ENGINE" 2>/dev/null \
  | grep -vE "^Timestamp|${NOISE}" | tail -n 30 | sed 's/^/  /'

echo
echo "Live: scripts/logs.sh --follow · detaliat: defaults write ${APP_ID} GDCFirewall.verboseLog -bool true"
