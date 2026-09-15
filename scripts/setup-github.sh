#!/bin/bash
# Creează depozitul pe GitHub sub contul gordasgdc și pornește GitHub Pages
# pe folderul docs/, cu domeniul personal gordas.dev.
# Autentificarea trece EXCLUSIV prin `gh` (Regula 2: niciun token în .git/config).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="gdc-firewall"
OWNER="gordasgdc"

cd "$REPO_ROOT"

command -v gh >/dev/null || { echo "gh CLI lipsește. brew install gh"; exit 1; }
gh auth status >/dev/null || { echo "Rulează: gh auth login"; exit 1; }

# GPL-3.0 e obligatorie (motorul LuLu e GPL-3.0). Textul complet se ia de la
# sursă, nu se rescrie de mână — o licență parafrazată nu e licența.
if [[ ! -f LICENSE ]]; then
  echo "→ Descarc textul GPL-3.0…"
  curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE
fi

if [[ ! -d .git ]]; then
  git init -b main
  git add .
  git commit -m "GDC Firewall v0.1.0 — schelet inițial (UI, blocklist, site)"
fi

if ! gh repo view "$OWNER/$REPO_NAME" >/dev/null 2>&1; then
  gh repo create "$OWNER/$REPO_NAME" \
    --public \
    --source=. \
    --remote=origin \
    --description "Firewall pentru macOS în limba română, pentru utilizatori non-tehnici. Motor: LuLu (Objective-See). GPL-3.0." \
    --push
else
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$OWNER/$REPO_NAME.git"
  git push -u origin main
fi

# Pagina de prezentare NU se publica din acest repo: domeniul gordas.dev e
# revendicat prin CNAME de `gdc-plugin-manager-catalog-vendor`, iar un domeniu
# apex poate apartine unui singur repo GitHub Pages. Pagina noastra devine
# subcalea gordas.dev/gdc-firewall in acel repo — vezi scripts/sync-site.sh.
"$REPO_ROOT/scripts/sync-site.sh" || true

echo
echo "Pasul manual rămas (nu-l poate face scriptul):"
echo "  1. Commit + push în gdc-plugin-manager-catalog-vendor (pagina gordas.dev/gdc-firewall)."
echo "  2. Cere Apple entitlement-ul com.apple.developer.networking.networkextension."
