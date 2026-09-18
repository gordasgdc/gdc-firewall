#!/usr/bin/env bash
# Semnare Developer ID + notarizare pentru GDC Firewall.
#
# Portat din modulul comun GDC (MediaFlow Monitor / GDCPluginManager), cu O
# DIFERENȚĂ ESENȚIALĂ: aplicația asta conține o extensie de sistem.
#
#   `codesign --deep` NU se folosește aici. `--deep` aplică ACELEAȘI
#   entitlements tuturor bundle-urilor imbricate — iar extensia și aplicația
#   au entitlements DIFERITE. Rezultatul ar fi o extensie semnată greșit, pe
#   care macOS refuză s-o încarce, cu o eroare care nu spune de ce.
#   Regula Apple e „dinăuntru spre afară”: întâi extensia, cu entitlements-ul
#   ei, apoi aplicația care o conține.
#
# Nu face NIMIC (iese cu succes, fără să semneze) dacă identitatea cerută nu e
# setată — build-ul rămâne ad-hoc, exact ca înainte.
#
# Utilizare:
#   codesigning/sign-and-notarize.sh app "/cale/catre/GDC Firewall.app"
#   codesigning/sign-and-notarize.sh pkg /cale/catre/GDCFirewall-2.0.0.pkg
set -euo pipefail

KIND="${1:?Utilizare: sign-and-notarize.sh <app|pkg> <cale>}"
TARGET="${2:?Utilizare: sign-and-notarize.sh <app|pkg> <cale>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ENT="$SCRIPT_DIR/../../../Engine/LuLu/LuLu/Extension/Extension.entitlements"
APP_ENT="$SCRIPT_DIR/GDCFirewall.entitlements"

sign_app() {
    local app_path="$1"

    # 1. Extensia de sistem, cu entitlements-ul EI.
    local sysex
    sysex="$(find "$app_path/Contents/Library/SystemExtensions" -maxdepth 1 \
             -name "*.systemextension" 2>/dev/null | head -n1)"
    if [ -n "$sysex" ]; then
        if [ ! -f "$ENGINE_ENT" ]; then
            echo "‼️  Nu găsesc $ENGINE_ENT — rulează întâi scripts/fetch-engine.sh." >&2
            exit 1
        fi
        echo "==> Semnez extensia de sistem: $(basename "$sysex")"
        codesign --force --timestamp --options runtime \
            --entitlements "$ENGINE_ENT" \
            --sign "$APPLE_SIGN_IDENTITY_APP" "$sysex"
    else
        # Nu e o eroare fatală: pachetul poate fi construit și fără extensie
        # (build de interfață). Dar e exact genul de lucru care trece
        # neobservat până la primul client, deci se spune tare.
        echo "⚠️  Bundle-ul NU conține nicio extensie de sistem."
        echo "    Aplicația va porni, dar nu va filtra nimic."
    fi

    # 2. Orice alt binar imbricat (dylib-uri, helpere) — fără entitlements
    #    speciale, doar semnat, ca să nu rupă semnătura părintelui.
    find "$app_path" \( -name "*.dylib" -o -name "*.so" \) -type f -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            codesign --force --timestamp --options runtime \
                --sign "$APPLE_SIGN_IDENTITY_APP" "$f"
        done

    # 3. Aplicația însăși, la final. Fără --deep, din motivul de sus.
    echo "==> Semnez aplicația…"
    codesign --force --timestamp --options runtime \
        --entitlements "$APP_ENT" \
        --sign "$APPLE_SIGN_IDENTITY_APP" "$app_path"

    echo "==> Verific semnătura…"
    codesign --verify --strict --verbose=2 "$app_path"
    [ -n "$sysex" ] && codesign --verify --strict --verbose=2 "$sysex"

    # Verificare separată de cea de mai sus: `codesign --verify` spune doar
    # că semnătura e coerentă, nu că entitlements-ul de NetworkExtension chiar
    # a ajuns în binar. Fără el, extensia nu se încarcă niciodată.
    echo "==> Verific entitlement-ul de NetworkExtension…"
    if codesign -d --entitlements :- "$app_path" 2>/dev/null \
        | grep -q "com.apple.developer.networking.networkextension"; then
        echo "    prezent."
    else
        echo "‼️  Entitlement-ul networkextension LIPSEȘTE din binarul semnat." >&2
        echo "    Profilul de semnare al contului nu îl acordă încă — vezi" >&2
        echo "    codesigning/apple-entitlement-request.md." >&2
        exit 1
    fi
}

notarize() {
    local target="$1"
    local upload_path

    echo "==> Împachetez pentru notarizare…"
    if [ -d "$target" ]; then
        upload_path="/tmp/notarize-$$.zip"
        ditto -c -k --keepParent "$target" "$upload_path"
    else
        upload_path="/tmp/notarize-$$.${target##*.}"
        cp "$target" "$upload_path"
    fi

    echo "==> Trimit la Apple (poate dura 1–15 min)…"
    if [ -n "${APPLE_NOTARY_KEY_ID:-}" ]; then
        local key_p8_path="/tmp/notary-key-$$.p8"
        printf '%s' "$APPLE_NOTARY_KEY_P8" > "$key_p8_path"
        # Cheia pleacă de pe disc indiferent cum se termină scriptul.
        trap 'rm -f "$key_p8_path"' RETURN
        xcrun notarytool submit "$upload_path" \
            --key "$key_p8_path" \
            --key-id "$APPLE_NOTARY_KEY_ID" \
            --issuer "$APPLE_NOTARY_ISSUER_ID" \
            --wait
    else
        xcrun notarytool submit "$upload_path" \
            --apple-id "$APPLE_ID" \
            --team-id "${APPLE_TEAM_ID:-8AR6XP8MG7}" \
            --password "$APPLE_APP_PASSWORD" \
            --wait
    fi

    echo "==> Capsez biletul (staple)…"
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
    rm -f "$upload_path"
}

case "$KIND" in
    app)
        if [ -z "${APPLE_SIGN_IDENTITY_APP:-}" ]; then
            echo "→ APPLE_SIGN_IDENTITY_APP nesetată — sar peste semnare."
            exit 0
        fi
        sign_app "$TARGET"
        # Aplicația se notarizează doar dacă e livrată ca atare; în fluxul
        # nostru pachetul .pkg e cel notarizat, deci pasul ăsta e opțional.
        [ -n "${NOTARIZE_APP:-}" ] && notarize "$TARGET"
        ;;
    notarize)
        # Doar notarizare, fără re-semnare: pentru un pachet semnat deja de
        # Xcode (scripts/build_engine_app.sh). Re-semnat aici, cu
        # entitlements-urile brute, ar pierde $(TeamIdentifierPrefix) expandat.
        notarize "$TARGET"
        ;;
    pkg)
        if [ -z "${APPLE_SIGN_IDENTITY_INSTALLER:-}" ]; then
            echo "→ APPLE_SIGN_IDENTITY_INSTALLER nesetată — sar peste semnare."
            exit 0
        fi
        echo "==> Semnez pachetul…"
        productsign --sign "$APPLE_SIGN_IDENTITY_INSTALLER" "$TARGET" "$TARGET.signed"
        mv "$TARGET.signed" "$TARGET"
        notarize "$TARGET"
        ;;
    *)
        echo "Tip necunoscut: $KIND (așteptat: app, notarize sau pkg)" >&2
        exit 2
        ;;
esac

echo "✓ Gata: $TARGET"
