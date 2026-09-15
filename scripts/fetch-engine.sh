#!/bin/bash
# Aduce motorul LuLu la un tag FIX și verifică, la fiecare rulare, că nimeni
# n-a atins partea intangibilă.
#
# „Intangibil” are acum o definiție executabilă, nu una din documentație:
# orice modificare sub `LuLu/Extension/` — cu excepția lui `Info.plist`, unde
# numele serviciului Mach trebuie să se potrivească cu cel din consts.h —
# oprește build-ul. Restul motorului ARE voie să difere: integrarea GDC îl
# rescrie intenționat (vezi integrate-engine.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$REPO_ROOT/Engine/LuLu"
ENGINE_URL="https://github.com/objective-see/LuLu.git"
ENGINE_TAG="v4.5.1"

if [[ ! -d "$ENGINE_DIR/.git" ]]; then
  echo "→ Clonez motorul LuLu ($ENGINE_TAG)…"
  git clone --depth 1 --branch "$ENGINE_TAG" "$ENGINE_URL" "$ENGINE_DIR"
else
  git -C "$ENGINE_DIR" fetch --depth 1 origin "refs/tags/$ENGINE_TAG:refs/tags/$ENGINE_TAG" 2>/dev/null || true
fi

CURRENT="$(git -C "$ENGINE_DIR" describe --tags --always 2>/dev/null || echo "necunoscut")"
if [[ "$CURRENT" != "$ENGINE_TAG" ]]; then
  echo "‼️  Motorul e pe '$CURRENT', nu pe '$ENGINE_TAG'."
  echo "    Dacă urci intenționat versiunea motorului, schimbă ENGINE_TAG aici,"
  echo "    apoi verifică Engine/XPCProtocols.swift și Engine/LuLuConstants.swift"
  echo "    rând cu rând: o semnătură XPC greșită nu dă eroare de compilare."
  exit 1
fi

# Fișierele extensiei, singurele care trebuie să rămână bit-cu-bit ca în
# upstream. Două excepții, ambele deliberate și amândouă declarații de
# identitate, nu comportament de filtrare:
#   - `Info.plist`        — numele serviciului Mach, care trebuie să
#                           coincidă cu cel din consts.h;
#   - `Extension.entitlements` — grupul de aplicații, prefixat cu Team ID-ul
#                           celui care semnează.
# Orice `.m`/`.h` din extensie rămâne interzis.
TOUCHED="$(git -C "$ENGINE_DIR" status --porcelain -- 'LuLu/Extension' \
           | grep -vE 'LuLu/Extension/(Info\.plist|Extension\.entitlements)$' || true)"

if [[ -n "$TOUCHED" ]]; then
  echo "‼️  Extensia de rețea a fost modificată. Motorul de filtrare NU se atinge:"
  echo "$TOUCHED"
  echo
  echo "    Orice comportament nou se implementează în macOS/GDCFirewall/."
  echo "    Ca să revii: git -C Engine/LuLu checkout -- LuLu/Extension"
  exit 1
fi

# Versiunea motorului trebuie sa fie aceeasi in trei locuri: tag-ul clonat,
# constanta din cod (pe care aplicatia o compara cu manifestul de pe server)
# si `engine_version_required` din update.json. Aici verificam primele doua;
# sync-site.sh o scrie pe a treia din prima.
CODE_ENGINE="$(sed -n 's/.*static let engineVersion = "\(.*\)".*/\1/p' \
  "$REPO_ROOT/macOS/GDCFirewall/Sources/GDCFirewall/Engine/LuLuConstants.swift")"
if [[ "$CODE_ENGINE" != "${ENGINE_TAG#v}" ]]; then
  echo "‼️  Motor clonat ${ENGINE_TAG#v}, dar LuLuConstants.swift zice $CODE_ENGINE."
  echo "    Verificarea de actualizari compara constanta aia cu serverul, deci"
  echo "    aplicatia ar raporta un motor pe care nu-l are. Aliniaza-le."
  exit 1
fi

if [[ -f "$ENGINE_DIR/.gdc-integrated" ]]; then
  echo "✓ Motor LuLu $ENGINE_TAG, integrat GDC (v$(cat "$ENGINE_DIR/.gdc-integrated")), extensie neatinsă."
else
  echo "✓ Motor LuLu $ENGINE_TAG. Rulează scripts/integrate-engine.sh pentru integrarea GDC."
fi
