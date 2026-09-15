#!/bin/bash
# Verifica ca integrarea cu motorul chiar compileaza — ambele tinte, Release.
#
# De ce exista, cu un caz real gasit in aceeasi sesiune in care a fost scris:
# lista de surse a tintei Xcode e un SNAPSHOT luat la integrare. Un fisier
# Swift nou adaugat dupa aceea nu intra singur in tinta. `swift build` (SPM)
# ramane verde, fiindca el vede folderul, nu proiectul — deci drift-ul e
# invizibil pana cand cineva construieste Release-ul si primeste
# "cannot find 'X' in scope" intr-un fisier pe care tocmai l-a scris.
#
# Reintegrarea e idempotenta, deci scriptul o ruleaza mereu inainte de build:
# asa lista de surse nu poate ramane in urma fata de disc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Engine/LuLu/LuLu/LuLu.xcodeproj"
CONFIG="${1:-Release}"

echo "→ Reintegrez (ca sursele noi sa intre in tinta)…"
bash "$ROOT/scripts/integrate-engine.sh" | grep -E "tinta|ținta|✓" || true

FAILED=0
for target in LuLu Extension; do
  label="$target"
  [ "$target" = "LuLu" ] && label="GDC Firewall (aplicatie)"
  [ "$target" = "Extension" ] && label="extensia de retea"

  printf "→ Compilez %s (%s)… " "$label" "$CONFIG"
  if xcodebuild -project "$PROJECT" -target "$target" -configuration "$CONFIG" \
       CODE_SIGNING_ALLOWED=NO build > "/tmp/gdcfw-build-$target.log" 2>&1; then
    echo "OK"
  else
    echo "ESUAT"
    grep -E "error:" "/tmp/gdcfw-build-$target.log" | head -20
    echo "    log complet: /tmp/gdcfw-build-$target.log"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo
echo "✓ Ambele tinte compileaza in $CONFIG."
echo "  Asta NU dovedeste ca filtrarea merge — pentru asta e nevoie de"
echo "  semnare Developer ID cu entitlement-ul aprobat si de un test manual"
echo "  pe un Mac real (vezi codesigning/README-notarizare.md, sectiunea 6)."
