#!/bin/bash
# Build-ul COMPLET: aplicația GDC integrată în proiectul Xcode al motorului,
# cu extensia de rețea înăuntru, semnate Developer ID.
#
# Diferit de build_app.sh, care construiește doar interfața (pachetul SPM,
# fără extensie). Ăsta e binarul care chiar filtrează.
#
# Semnează Xcode, nu `codesign` de mână: entitlements-urile și Info.plist-ul
# extensiei conțin $(TeamIdentifierPrefix), pe care doar Xcode îl expandează.
# Semnate cu fișierul brut, grupul de aplicații și serviciul Mach al extensiei
# ar rămâne cu textul literal și aplicația n-ar mai găsi extensia.
#
# Utilizare:
#   ./scripts/build_engine_app.sh             build + verificare
#   NOTARIZE=1 ./scripts/build_engine_app.sh  + notarizare (credențiale ca în
#                                               codesigning/sign-and-notarize.sh)
set -euo pipefail
# Sub pipefail, `cmd | grep -q` pică fals când grep iese la prima potrivire și
# `cmd` primește SIGPIPE. Verificările citesc deci prin `grep … < <(cmd)`.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Engine/LuLu/LuLu/LuLu.xcodeproj"
TEAM_ID="8AR6XP8MG7"
IDENTITY="Developer ID Application: DUMITRU CRISTINEL GORDAS (${TEAM_ID})"
EXT_ID="dev.gordas.GDCFirewall.extension"
CERT_DIR="$HOME/Developer/Certificates"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
SYMROOT="$ROOT/Build/engine"
DIST_DIR="$ROOT/dist"

fail() { echo "‼️  $*" >&2; exit 1; }

# Regula 23: un dist/ deținut de root face ca scrierea să eșueze criptic.
if [ -d "$DIST_DIR" ] && { ! [ -w "$DIST_DIR" ] || find "$DIST_DIR" -maxdepth 2 -user root -print -quit 2>/dev/null | grep -q .; }; then
  echo "EROARE: 'dist/' contine fisiere detinute de root. Ruleaza manual:" >&2
  echo "    sudo rm -rf ${DIST_DIR}" >&2
  exit 1
fi

# --- 1. Identitatea de semnare -----------------------------------------
grep -qF "$IDENTITY" < <(security find-identity -v -p codesigning) \
  || fail "Lipseste din Keychain: ${IDENTITY}"

# --- 2. Integrarea — reaplicată mereu (lista de surse e un instantaneu) --
bash "$ROOT/scripts/integrate-engine.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/macOS/GDCFirewall/Resources/Info.plist")"

# --- 3. Profilele de provizionare --------------------------------------
# Fără profil, macOS omoară la pornire orice binar cu entitlements
# restricționate (networkextension, system-extension.install) — aplicația
# nici nu apucă să ceară activarea extensiei.
profile_plist() { security cms -D -i "$1" 2>/dev/null; }
profile_field() { profile_plist "$1" | plutil -extract "$2" raw -o - - 2>/dev/null; }

# Orice .provisionprofile din ~/Developer/Certificates ajunge unde îl caută Xcode.
mkdir -p "$PROFILE_DIR"
# Un profil regenerat primește alt UUID: versiunea veche, cu același nume,
# se șterge, altfel Xcode poate alege tot profilul fără capabilitatea nouă.
for f in "$CERT_DIR"/*.provisionprofile; do
  [ -f "$f" ] || continue
  uuid="$(profile_field "$f" UUID || true)"
  [ -n "$uuid" ] || continue
  pname="$(profile_field "$f" Name || true)"
  for old in "$PROFILE_DIR"/*.provisionprofile; do
    [ -f "$old" ] && [ "$(basename "$old")" != "${uuid}.provisionprofile" ] \
      && [ "$(profile_field "$old" Name || true)" = "$pname" ] && rm -f "$old"
  done
  cp "$f" "$PROFILE_DIR/${uuid}.provisionprofile"
done

# Numele cerute vin din proiect (le scrie integrate-engine.sh), nu tastate
# a doua oară aici.
build_setting() {  # $1 = ținta, $2 = cheia
  xcodebuild -project "$PROJECT" -target "$1" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' -v k="$2" '$1 ~ "^ *"k"$" {print $2; exit}'
}
required_profile() { build_setting "$1" PROVISIONING_PROFILE_SPECIFIER; }

# Cheile com.apple.developer.* din entitlements trebuie să existe în profil:
# fiecare corespunde unei capabilități bifate pe App ID. Una lipsă = Xcode
# refuză semnarea, iar mesajul lui nu spune ce anume să bifezi în portal.
missing_capabilities() {  # $1 = ținta, $2 = profilul
  local ent="$(dirname "$PROJECT")/$(build_setting "$1" CODE_SIGN_ENTITLEMENTS)"
  python3 - "$ent" <(profile_plist "$2" | plutil -extract Entitlements json -o - -) <<'PY'
import json, plistlib, sys
wanted = [k for k in plistlib.load(open(sys.argv[1], "rb")) if k.startswith("com.apple.developer.")]
granted = json.load(open(sys.argv[2]))
print("\n".join(k for k in wanted if k not in granted))
PY
}

MISSING=0
CAP_MISSING=0
for target in LuLu Extension; do
  name="$(required_profile "$target")"
  [ -n "$name" ] || fail "Tinta ${target} nu are PROVISIONING_PROFILE_SPECIFIER — integrarea e veche?"
  found=""
  for f in "$PROFILE_DIR"/*.provisionprofile; do
    [ -f "$f" ] && [ "$(profile_field "$f" Name || true)" = "$name" ] && found="$f"
  done
  if [ -z "$found" ]; then
    echo "‼️  Lipseste profilul „${name}” (tinta ${target})." >&2
    MISSING=1
    continue
  fi
  [ "$(profile_field "$found" TeamIdentifier.0 || true)" = "$TEAM_ID" ] \
    || fail "Profilul „${name}” nu e al echipei ${TEAM_ID}."
  grep -q "content-filter-provider-systemextension" < <(profile_plist "$found") \
    || fail "Profilul „${name}” nu acorda content-filter-provider-systemextension. Bifeaza Network Extensions pe App ID si regenereaza-l."
  lacking="$(missing_capabilities "$target" "$found")"
  if [ -n "$lacking" ]; then
    app_id="$(profile_field "$found" Entitlements.com\\.apple\\.application-identifier || true)"
    echo "‼️  Profilul „${name}” nu include:" >&2
    echo "$lacking" | sed 's/^/      /' >&2
    echo "    Bifeaza capabilitatea corespunzatoare pe App ID-ul ${app_id#${TEAM_ID}.}" >&2
    echo "    (system-extension.install = System Extension), apoi Profiles → profilul" >&2
    echo "    „${name}” → Edit → Save → Download, peste cel din ${CERT_DIR}/." >&2
    CAP_MISSING=1
    continue
  fi
  echo "✓ Profil „${name}” (${target})"
done

if [ "$MISSING" -ne 0 ]; then
  APP_PROFILE="$(required_profile LuLu)"
  EXT_PROFILE="$(required_profile Extension)"
  cat >&2 <<EOF

Pasii, o singura data, pe developer.apple.com → Certificates, Identifiers & Profiles:
  1. Identifiers → + → App IDs → App → Explicit:
       dev.gordas.GDCFirewall            bifeaza Network Extensions + System Extension
       ${EXT_ID}  bifeaza Network Extensions
  2. Profiles → + → Distribution → Developer ID, cate unul pentru fiecare App ID,
     cu certificatul Developer ID Application, numite EXACT:
       ${APP_PROFILE}
       ${EXT_PROFILE}
  3. Descarca ambele .provisionprofile in ${CERT_DIR}/ si ruleaza din nou.
EOF
  exit 1
fi
[ "$CAP_MISSING" -eq 0 ] || exit 1

# --- 4. Build + semnare ------------------------------------------------
mkdir -p "$SYMROOT"
LOG="$SYMROOT/xcodebuild.log"
printf "→ Compilez si semnez GDC Firewall %s (Release, Developer ID)… " "$VERSION"
if xcodebuild -project "$PROJECT" -target LuLu -configuration Release \
     SYMROOT="$SYMROOT" OTHER_CODE_SIGN_FLAGS="--timestamp" \
     CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build > "$LOG" 2>&1; then
  echo "OK"
else
  echo "ESUAT"
  grep -E "error:" "$LOG" | head -20
  fail "log complet: ${LOG}"
fi

APP="$SYMROOT/Release/GDC Firewall.app"
SYSEX="$APP/Contents/Library/SystemExtensions/${EXT_ID}.systemextension"

# --- 5. Verificare ------------------------------------------------------
# Fiecare verificare prinde un defect care altfel apare abia pe Mac-ul
# clientului, ca o extensie care „nu se activează”, fără alt mesaj.
[ -d "$APP" ] || fail "Nu gasesc ${APP}"
[ -d "$SYSEX" ] || fail "Extensia lipseste din pachet sau nu poarta numele bundle ID-ului: ${SYSEX}"
codesign --verify --strict --deep "$APP" || fail "Semnatura pachetului nu e valida."

for b in "$APP" "$SYSEX"; do
  label="$(basename "$b")"
  info="$(codesign -dv "$b" 2>&1)"
  ents="$(codesign -d --entitlements :- "$b" 2>/dev/null)"
  echo "$info" | grep -q "TeamIdentifier=${TEAM_ID}" || fail "${label}: nu e semnat de echipa ${TEAM_ID}."
  echo "$info" | grep -q "flags=.*runtime" || fail "${label}: lipseste hardened runtime (notarizarea l-ar respinge)."
  [ -f "$b/Contents/embedded.provisionprofile" ] || fail "${label}: lipseste profilul inclus."
  echo "$ents" | grep -q "content-filter-provider-systemextension" || fail "${label}: lipseste entitlement-ul de filtru."
  if echo "$ents" | grep -q '\$('; then fail "${label}: entitlements cu variabile neexpandate."; fi
  # Xcode îl injectează implicit și la `build`, nu doar în Debug.
  # Notarizarea respinge orice binar care îl are.
  if echo "$ents" | grep -q "get-task-allow"; then fail "${label}: contine get-task-allow (depanabil, notarizarea l-ar respinge)."; fi
done

# O clasă principală care nu există în binar = aplicația se închide instant
# la pornire („Unable to find class”), deși build-ul și semnătura sunt curate.
PRINCIPAL="$(plutil -extract NSPrincipalClass raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -n "$PRINCIPAL" ] && [ "$PRINCIPAL" != "NSApplication" ]; then
  grep -q "_OBJC_CLASS_\$_${PRINCIPAL}\$" < <(nm "$APP/Contents/MacOS/GDC Firewall" 2>/dev/null) \
    || fail "NSPrincipalClass=${PRINCIPAL} nu exista in binar — aplicatia s-ar inchide la pornire."
fi

MACH="$(plutil -extract NetworkExtension.NEMachServiceName raw -o - "$SYSEX/Contents/Info.plist")"
[ "${MACH#${TEAM_ID}.}" != "$MACH" ] || fail "NEMachServiceName neexpandat: ${MACH}"

# Aceeași cerință pe care extensia o pune clienților XPC (Extension/XPCListener.m),
# construită din consts.h. Dacă aplicația n-o satisface, extensia refuză
# conexiunea și interfața rămâne fără nicio regulă și nicio alertă.
CONSTS="$(dirname "$PROJECT")/Shared/consts.h"
define() { sed -nE "s/^#define[[:space:]]+$1[[:space:]]+@?\"([^\"]*)\".*/\1/p" "$CONSTS" | head -n1; }
REQ="anchor apple generic and identifier \"$(define APP_ID)\" and certificate leaf [subject.CN] = \"$(define SIGNING_AUTH)\" and info [CFBundleShortVersionString] >= \"2.0.0\""
codesign --verify -R="$REQ" "$APP" 2>/dev/null || fail "Aplicatia nu satisface cerinta XPC a extensiei: ${REQ}"
# Daemon-ul GDC NU are voie să scrie în folderul unui LuLu real instalat pe
# același Mac — i-ar citi și modifica regulile (s-a întâmplat, v2.0.x).
EXT_BIN="$SYSEX/Contents/MacOS/${EXT_ID}"
if grep -qF "/Library/Objective-See/LuLu" < <(strings "$EXT_BIN"); then
  fail "Extensia foloseste inca /Library/Objective-See/LuLu (INSTALL_DIRECTORY din consts.h)."
fi

# Serviciul pe care îl caută aplicația (LuLuConstants.swift) trebuie să fie
# exact cel pe care îl ascultă extensia. Altfel: filtru pornit, „Motor oprit”
# în meniu, nicio alertă — și nicio eroare nicăieri.
grep -qxF "$MACH" < <(strings "$APP/Contents/MacOS/GDC Firewall") \
  || fail "Aplicatia nu cauta serviciul Mach al extensiei (${MACH}) — vezi LuLuConstants.swift."

echo "✓ Semnatura, profile, entitlements, serviciul Mach (${MACH}) si cerinta XPC verificate."

# --- 6. Notarizare (optional) + arhivă versionată (Regula 17) ------------
if [ -n "${NOTARIZE:-}" ]; then
  "$ROOT/macOS/GDCFirewall/codesigning/sign-and-notarize.sh" notarize "$APP"
fi

mkdir -p "$DIST_DIR"
ZIP="$DIST_DIR/GDCFirewall-${VERSION}-complet-test.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

cat <<EOF

✅ GDC Firewall ${VERSION}, complet (aplicatie + extensie), semnat Developer ID.
   Aplicatie: ${APP}
   Arhiva:    ${ZIP}

Test local:
  1. ditto "${APP}" "/Applications/GDC Firewall.app"
     (macOS activeaza extensii de sistem DOAR din /Applications)
  2. Porneste aplicatia din /Applications si aproba extensia in
     Setari de sistem → General → Articole de login si extensii.
EOF
