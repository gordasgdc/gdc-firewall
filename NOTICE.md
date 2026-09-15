# Atribuiri obligatorii

GDC Firewall e un **strat de interfață** construit peste motorul de filtrare
open-source **LuLu**.

- **LuLu** — © Objective-See, LLC (Patrick Wardle) — https://github.com/objective-see/LuLu
  Licență: GPL-3.0. Motorul e vendorat neschimbat în `Engine/LuLu/`
  (`scripts/fetch-engine.sh`), la un tag fix.
- **StevenBlack/hosts** — listele de domenii folosite de modulul
  „Filtrare & AdBlock” — https://github.com/StevenBlack/hosts
  Licență: MIT. Listele se descarcă la cerere, nu sunt incluse în pachet.

Fiindcă GDC Firewall se leagă de un motor GPL-3.0, **întregul produs se
distribuie sub GPL-3.0**, cu sursa publică. Nota de copyright Objective-See
apare în ecranul „Despre”, în `README.md` și aici — e o obligație a licenței,
nu o preferință editorială, și nu se scoate la niciun redesign.

Autorul stratului GDC (interfață, dicționar de procese, Auto-Pilot, modul de
filtrare, site): **Cristi Gordaș / GDC**.
