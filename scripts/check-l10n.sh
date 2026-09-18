#!/bin/bash
# Verifică traducerile interfeței (RO sursă → EN, ES).
#
#   1. Fiecare cheie din cod — `L("…")` — și fiecare nume/explicație din
#      ProcessDictionary.json există în en.lproj/GDC.strings și es.lproj/GDC.strings.
#   2. O traducere are exact aceiași specificatori (%@, %d) ca cheia. Altfel
#      `String(format:)` citește argumente greșite — crash, nu doar text urât.
#   3. Niciun text de interfață nu a rămas scris direct, neîmpachetat în L().
#
# Pică (exit 1) la orice problemă, ca build_app.sh / build_engine_app.sh să
# nu producă un binar pe jumătate tradus.
#
# Utilizare: scripts/check-l10n.sh [--list]   (--list tipărește cheile din cod)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/macOS/GDCFirewall/Sources/GDCFirewall"

python3 - "$SRC" "${1:-}" <<'PY'
import json, pathlib, re, subprocess, sys

src = pathlib.Path(sys.argv[1])
list_only = sys.argv[2] == "--list"

def unescape(lit):
    out, i = [], 0
    while i < len(lit):
        c = lit[i]
        if c == "\\" and i + 1 < len(lit):
            n = lit[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(n, "\\" + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)

key_re = re.compile(r'(?<![A-Za-z0-9_.])L\(\s*"((?:[^"\\]|\\.)*)"')
keys = {}
for f in sorted(src.rglob("*.swift")):
    for n, line in enumerate(f.read_text().splitlines(), 1):
        for m in key_re.finditer(line):
            keys.setdefault(unescape(m.group(1)), f"{f.relative_to(src)}:{n}")

catalog = json.loads((src / "Resources/ProcessDictionary.json").read_text())
for proc, entry in catalog["entries"].items():
    for field in ("name", "detail"):
        keys.setdefault(entry[field], f"ProcessDictionary.json:{proc}.{field}")

if list_only:
    for k in sorted(keys):
        print(json.dumps(k, ensure_ascii=False))
    sys.exit(0)

spec_re = re.compile(r"%(?:\d+\$)?[@dDuUxXfeEgGcCsSpaAF]|%%")
def specs(s):
    return sorted(x for x in spec_re.findall(s) if x != "%%")

failed = False
for lang in ("en", "es"):
    path = src / "Resources" / f"{lang}.lproj" / "GDC.strings"
    if not path.exists():
        print(f"‼️  Lipseste {path.relative_to(src)}")
        failed = True
        continue
    try:
        table = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                                          check=True, capture_output=True).stdout)
    except subprocess.CalledProcessError as e:
        print(f"‼️  {lang}: GDC.strings nu se poate citi — {e.stderr.decode().strip()}")
        failed = True
        continue
    missing = [k for k in keys if k not in table]
    for k in missing:
        print(f"‼️  {lang}: lipseste traducerea pentru {json.dumps(k, ensure_ascii=False)} ({keys[k]})")
    for k, v in table.items():
        if k in keys and specs(k) != specs(v):
            print(f"‼️  {lang}: specificatori diferiti {specs(k)} ≠ {specs(v)} pentru {json.dumps(k, ensure_ascii=False)}")
            failed = True
        if k in keys and not v.strip():
            print(f"‼️  {lang}: traducere goala pentru {json.dumps(k, ensure_ascii=False)}")
            failed = True
    unused = [k for k in table if k not in keys]
    for k in unused:
        print(f"⚠️  {lang}: cheie nefolosita {json.dumps(k, ensure_ascii=False)}")
    failed |= bool(missing)

# Texte de interfață rămase neîmpachetate. Mărcile și „OK” nu se traduc.
ALLOWED = {"OK", "GDC Firewall", "—"}
ui_re = re.compile(
    r'(?:\b(?:Text|Button|Toggle|Label|TextField|Picker|Section|DisclosureGroup|LabeledContent|ProgressView|Window|MenuBarExtra)\(\s*'
    r'|\.help\(\s*|\.accessibilityLabel\(\s*|withTitle:\s*|setStatus\(\s*|title:\s*'
    r'|(?:messageText|informativeText|message)\s*=\s*)"((?:[^"\\]|\\.)*)"')
for f in sorted(src.rglob("*.swift")):
    for n, line in enumerate(f.read_text().splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        for m in ui_re.finditer(line):
            text = unescape(m.group(1))
            if text in ALLOWED or text.startswith("©") or not re.search(r"[A-Za-zĂÂÎȘȚăâîșț]", text) or text.startswith("\\("):
                continue
            print(f"‼️  text neimpachetat in L(): {f.relative_to(src)}:{n}: {json.dumps(text, ensure_ascii=False)}")
            failed = True

# `L(variabilă)` scapă verificării de mai sus: cheia nu apare în cod. Permis
# doar unde cheile vin dintr-o sursă verificată separat (ProcessDictionary.json).
DYNAMIC_OK = {"Alerts/ProcessCatalog.swift"}
dyn_re = re.compile(r'(?<![A-Za-z0-9_.])L\((?!\s*")')
for f in sorted(src.rglob("*.swift")):
    rel = str(f.relative_to(src))
    for n, line in enumerate(f.read_text().splitlines(), 1):
        code = line.split("//")[0]
        if "func L(" in code or rel in DYNAMIC_OK:
            continue
        if dyn_re.search(code):
            print(f"‼️  L() cu cheie dinamica, nevazuta de verificare: {rel}:{n}")
            failed = True

if failed:
    sys.exit(1)
print(f"✓ Traduceri complete: {len(keys)} texte, EN + ES.")
PY
