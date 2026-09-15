# Cerere de entitlement către Apple — `content-filter-provider`

Document de lucru pentru formularul Apple
(<https://developer.apple.com/contact/request/network-extension-entitlement/>).

**Nu îl poate trimite nimeni în locul tău**: cererea se completează din contul
Developer al lui Cristi Gordaș (Team ID `8AR6XP8MG7`), iar răspunsul Apple
vine pe e-mailul contului. Textele de mai jos sunt gata de copiat în câmpurile
formularului.

---

## Ce se cere, exact

| Câmp | Valoare |
|---|---|
| Team ID | `8AR6XP8MG7` |
| App name | GDC Firewall |
| Bundle ID (aplicație) | `dev.gordas.GDCFirewall` |
| Bundle ID (extensie) | `dev.gordas.GDCFirewall.extension` |
| Platformă | macOS 13+ |
| Distribuție | Developer ID (în afara Mac App Store) |
| Entitlement | `com.apple.developer.networking.networkextension` → `content-filter-provider-systemextension` |
| Suplimentar | `com.apple.developer.system-extension.install` |

Fără acest entitlement, aplicația se compilează și pornește, dar extensia nu se
încarcă niciodată — e un blocaj de cont, nu de cod. Scriptul
`sign-and-notarize.sh` verifică explicit prezența lui în binarul semnat și
oprește build-ul dacă lipsește, ca să nu se publice un pachet care pare bun și
nu filtrează nimic.

---

## Descrierea aplicației (câmpul „App description”)

> GDC Firewall is a free, open-source outbound firewall for macOS, published in
> Romanian for non-technical users. It notifies the user when an application
> attempts to open a network connection and lets them allow or block it, with a
> plain-language explanation of what the process is and a colour-coded risk
> assessment based on the process's code signature.
>
> It is distributed free of charge under the GPL-3.0 licence, with public source
> code, by an independent developer (Cristi Gordaș / GDC).

## De ce e nevoie de entitlement (câmpul „Why do you need this entitlement?”)

> The application's entire purpose is to let the user see and control outbound
> network connections made by software running on their own Mac. That requires a
> `NEFilterDataProvider` running as a system extension: there is no other API on
> macOS that can observe and decide on per-process outbound flows.
>
> The filtering engine is LuLu, the established open-source macOS firewall by
> Objective-See (Patrick Wardle), which already ships with this entitlement.
> GDC Firewall is a derivative work: the network extension and its filtering
> logic are used unmodified; what this project adds is a redesigned user
> interface in Romanian, a plain-language dictionary that translates system
> process names into descriptions an ordinary user can act on, and an optional
> domain blocklist built on the public StevenBlack hosts lists.
>
> Because the product links against a GPL-3.0 engine, the whole application is
> distributed under GPL-3.0 with public source, and the Objective-See copyright
> notice is retained in the About window, the README and a NOTICE file.

## Ce face concret extensia (câmpul „How will the extension be used?”)

> The `NEFilterDataProvider` evaluates outbound flows only. For each new flow it
> looks up an existing user rule; if none exists, it asks the user interface,
> over XPC, to present an alert, and applies the user's answer. Rules are stored
> locally on the user's machine.
>
> No network traffic content is inspected, recorded, proxied or transmitted
> anywhere. No telemetry or analytics of any kind is collected. Domain blocklists
> are downloaded from a public GitHub repository and evaluated entirely on
> device; no browsing data leaves the Mac.

## Confidențialitate (dacă formularul cere)

> The application collects nothing. There is no account, no licence server, no
> analytics endpoint and no crash reporting. The only outbound requests the app
> itself makes are: (1) fetching an update manifest from gordas.dev, and
> (2) downloading the public StevenBlack hosts list when the user enables domain
> filtering.

---

## Pași, în ordine

1. Cristi trimite formularul cu textele de mai sus, de pe contul Developer.
2. Răspunsul Apple vine pe e-mail — de regulă în câteva zile lucrătoare, uneori
   cu întrebări suplimentare. Nu există o cale de a-l grăbi.
3. După aprobare: **regenerează profilul de semnare** din Apple Developer
   (Certificates, Identifiers & Profiles). Entitlement-ul se acordă pe App ID,
   deci trebuie să existe două App ID-uri, cu capabilitatea activată pe ambele:
   - `dev.gordas.GDCFirewall`
   - `dev.gordas.GDCFirewall.extension`
4. Rulează `./scripts/build_app.sh` cu `APPLE_SIGN_IDENTITY_APP` setat.
   Scriptul de semnare verifică singur că entitlement-ul a ajuns în binar.
5. Abia după asta are sens testul real pe un Mac: instalare, aprobarea
   extensiei din Setări de sistem, apoi o alertă reală.

## Ce NU trece niciodată prin chat

Certificatele (`.p12`), cheile de notarizare (`.p8`) și parolele specifice
aplicației stau exclusiv în `~/Developer/Certificates/`, în afara oricărui
repo git (Regula 1). Nu se lipesc în conversație și nu se comit, indiferent de
`.gitignore`.
