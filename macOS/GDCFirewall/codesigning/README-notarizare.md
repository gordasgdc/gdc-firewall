# Checklist de semnare și notarizare — GDC Firewall

De parcurs în ordine, o dată per release. Fiecare pas are o verificare care
produce o ieșire, nu o impresie (Regula 36).

---

## 0. Precondiții (o singură dată per cont)

- [ ] Entitlement-ul `content-filter-provider-systemextension` aprobat de Apple
      pe Team ID `8AR6XP8MG7` → vezi `apple-entitlement-request.md`.
- [ ] App ID-uri create, cu capabilitatea activată pe **amândouă**:
      `dev.gordas.GDCFirewall` și `dev.gordas.GDCFirewall.extension`.
- [ ] Certificat **Developer ID Application** în Keychain:
      ```bash
      security find-identity -v -p codesigning | grep "Developer ID Application"
      ```
- [ ] Certificat **Developer ID Installer** (pentru `.pkg`):
      ```bash
      security find-identity -v | grep "Developer ID Installer"
      ```
- [ ] Cheie de notarizare (`.p8`) sau parolă specifică aplicației, ținute în
      `~/Developer/Certificates/` — niciodată în repo.

## 1. Variabile de mediu

```bash
export APPLE_SIGN_IDENTITY_APP="Developer ID Application: DUMITRU CRISTINEL GORDAS (8AR6XP8MG7)"
export APPLE_SIGN_IDENTITY_INSTALLER="Developer ID Installer: DUMITRU CRISTINEL GORDAS (8AR6XP8MG7)"
export APPLE_TEAM_ID="8AR6XP8MG7"

# Varianta cu cheie API (preferată — nu expune parola contului):
export APPLE_NOTARY_KEY_ID="..."
export APPLE_NOTARY_ISSUER_ID="..."
export APPLE_NOTARY_KEY_P8="$(cat ~/Developer/Certificates/AuthKey_XXXX.p8)"

# Sau varianta clasică:
# export APPLE_ID="dumitrugdc@gmail.com"
# export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

- [ ] Verifică fără să semnezi nimic:
      `codesign --display --verbose=2 /Applications/Safari.app 2>&1 | head -3`

## 2. Înainte de build

- [ ] Motorul e la tag și extensia e neatinsă: `./scripts/fetch-engine.sh`
- [ ] Integrarea e aplicată: `./scripts/integrate-engine.sh`
- [ ] Versiunea e ≥ 2.0.0 (cerință a extensiei, vezi `XPCListener.m`) și e
      sincronă în `Info.plist`, `gdc-manifest.json`, `docs/update.json`.
- [ ] `CHANGELOG.md` are intrarea versiunii (Regula 25).
- [ ] Ghidul e regenerat: `swift installer/generate-guide.swift` (îl rulează și `build_app.sh`)
- [ ] Preflight-ul ecosistemului:
      `~/Developer/_gdc-tools/preflight-release.sh <versiune>`

## 3. Build + semnare

```bash
./scripts/build_app.sh
```

- [ ] Scriptul NU a afișat avertismentul de semnare ad-hoc.
- [ ] Extensia de sistem e semnată separat, cu entitlements-ul ei
      (`sign-and-notarize.sh` o face; `--deep` nu se folosește niciodată aici —
      ar aplica entitlements-ul aplicației peste extensie și macOS ar refuza
      s-o încarce, fără să spună de ce).
- [ ] Entitlement-ul chiar a ajuns în binar — verificarea e automată în script,
      dar se poate face și manual:
      ```bash
      codesign -d --entitlements :- "Build/macOS/GDC Firewall.app" | grep networkextension
      ```
- [ ] Semnătura e validă:
      ```bash
      codesign --verify --strict --verbose=2 "Build/macOS/GDC Firewall.app"
      spctl --assess --type execute --verbose "Build/macOS/GDC Firewall.app"
      ```

## 4. Notarizare

- [ ] `xcrun notarytool submit ... --wait` s-a încheiat cu `status: Accepted`.
      La `Invalid`, citește motivul real, nu ghici:
      ```bash
      xcrun notarytool log <submission-id> --key ... --key-id ... --issuer ...
      ```
- [ ] Biletul e capsat și validat:
      ```bash
      xcrun stapler validate "dist/GDCFirewall-<versiune>.pkg"
      ```
- [ ] Gatekeeper acceptă pachetul pe o mașină care nu l-a mai văzut:
      ```bash
      spctl --assess --type install --verbose "dist/GDCFirewall-<versiune>.pkg"
      ```

## 5. Publicare

- [ ] Ambele nume ajung pe release: cel versionat **și** cel stabil
      (Regula 17) — `GDCFirewall-<versiune>.pkg` și `GDCFirewall.pkg`.
- [ ] Arhiva are exact trei fișiere la rădăcină (Regula 6): `.pkg`,
      `Dezinstalare_GDCFirewall.command`, `Instructiuni_Utilizare.pdf`.
- [ ] Site-ul e sincronizat: `./scripts/sync-site.sh`, apoi commit + push în
      `gdc-plugin-manager-catalog-vendor`.
- [ ] Fluxul de actualizare verificat live, nu presupus (Regula 35):
      ```bash
      ~/Developer/_gdc-tools/verify-update-flow.sh \
        https://gordas.dev/gdc-firewall/update.json <versiune> \
        https://github.com/gordasgdc/gdc-firewall/releases/latest/download/GDCFirewall.pkg
      ```
- [ ] Notele publice de release nu conțin nume proprii, citate din conversații
      sau explicații de debugging (Regula 29).

## 6. Test manual, obligatoriu (nu poate fi automatizat)

Pașii de mai jos cer interacțiune fizică cu ferestre de sistem. Nicio
verificare automată nu îi acoperă, iar fără ei fluxul **nu** e dovedit:

- [ ] Instalare din `.pkg` pe un Mac curat.
- [ ] Aprobarea extensiei în Setări de sistem → General → Elemente de
      conectare și extensii → Extensii de rețea.
- [ ] Meniul din bara de sus arată „Protecție activă”.
- [ ] O alertă reală apare, iar „Permite”/„Blochează” chiar are efect.
- [ ] Regula apărută se vede în panoul de reguli, în categoria corectă.
- [ ] Dezinstalatorul curăță complet.
