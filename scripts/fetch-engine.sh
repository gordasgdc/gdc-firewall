#!/bin/bash
# Aduce motorul LuLu la un tag FIX și verifică, la fiecare rulare, că nu are
# modificări locale. Motorul e intangibil (CLAUDE.md, Partea 2): dacă
# scriptul găsește diferențe, build-ul se oprește — o modificare accidentală
# în extensia de rețea nu trebuie să ajungă niciodată într-un pachet semnat.
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
  echo "    Dacă urci intenționat versiunea motorului, schimbă ENGINE_TAG aici"
  echo "    și verifică semnăturile XPC din Engine/DaemonBridge.swift."
  exit 1
fi

if [[ -n "$(git -C "$ENGINE_DIR" status --porcelain)" ]]; then
  echo "‼️  Motorul LuLu are modificări locale. Motorul NU se modifică —"
  echo "    orice comportament nou se implementează în macOS/GDCFirewall/."
  git -C "$ENGINE_DIR" status --short
  exit 1
fi

echo "✓ Motor LuLu $ENGINE_TAG, curat."
