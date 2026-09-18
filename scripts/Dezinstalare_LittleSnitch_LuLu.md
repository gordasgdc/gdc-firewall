# Dezinstalare completă Little Snitch și LuLu

Un singur fișier, `Dezinstalare_LittleSnitch_LuLu.command`, curăță complet
Little Snitch și LuLu de pe Mac — util înainte de a instala GDC Firewall sau
alt firewall. Durează 1–2 minute.

## Ce face

- Oprește Little Snitch și LuLu și le scoate extensiile de rețea prin
  mecanismul oficial macOS.
- Oprește serviciile lor de fundal și șterge aplicațiile, preferințele,
  cache-urile și logurile lor.
- **Nu șterge nimic definitiv**: totul ajunge în Coș, într-un folder numit
  „Firewall-uri eliminate” urmat de dată. Poți recupera orice de acolo.
- **Nu atinge** GDC Firewall, BlockBlock sau alte aplicații.

## Înainte de a începe

1. **Păstrezi regulile?** Exportă-le întâi: și Little Snitch, și LuLu au o
   comandă de export în fereastra lor de reguli. GDC Firewall le poate
   importa ulterior.
2. Salvează ce lucrezi: la final s-ar putea să fie nevoie de o repornire.

## Pașii

1. Salvează fișierul `Dezinstalare_LittleSnitch_LuLu.command` în **Descărcări**.
2. Deschide **Terminal**: apasă `⌘ + Spațiu`, scrie `Terminal`, apasă `Enter`.
3. În fereastra Terminal scrie `bash` urmat de un **spațiu** (nu apăsa încă
   Enter), apoi **trage fișierul** din Finder în fereastra Terminal. Apare
   calea lui. Apasă `Enter`.
   Dacă fișierul e în Descărcări, poți scrie direct:
   ```
   bash ~/Downloads/Dezinstalare_LittleSnitch_LuLu.command
   ```
4. Ți se cere **parola Mac-ului** (cea de la pornire). Cât o tastezi nu apare
   nimic pe ecran — e normal. Apasă `Enter` la final.
5. Scriptul arată lista cu tot ce a găsit. Citește-o, apoi scrie `da` și
   apasă `Enter`. Orice altceva anulează, fără nicio modificare.
6. Dacă apare **„Terminal dorește să controleze Finder”**, apasă **OK**.
   Finder mută aplicațiile la Coș, iar macOS le scoate astfel extensiile de
   rețea.
7. Dacă macOS îți cere parola într-o **fereastră** (pentru extensii), introdu-o.
8. La final apare **Verificare**, cu un ✓ pentru fiecare parte curățată.
   Dacă scrie că extensiile **dispar definitiv după următoarea repornire**,
   repornește Mac-ul când poți.

> **Dublu-click** pe fișier funcționează doar dacă macOS îl lasă să se
> deschidă. Dacă apare un mesaj că fișierul „nu poate fi deschis” sau că
> Apple nu l-a putut verifica, folosește metoda de mai sus, cu Terminal. Nu
> e nevoie să oprești nicio protecție a Mac-ului.

## Doar vrei să vezi ce ar face?

Previzualizarea arată lista și planul fără să modifice nimic:

```
bash ~/Downloads/Dezinstalare_LittleSnitch_LuLu.command --dry-run
```

## Dacă verificarea arată ceva rămas

- **Extensie încă activă** — **Setări de sistem** (*System Settings*) →
  **General** → **Elemente de login și extensii** (*Login Items &
  Extensions*) → **Extensii de rețea** (*Network Extensions*): oprește
  Little Snitch / LuLu, apoi repornește Mac-ul.
- **Filtru rămas în listă** — **Setări de sistem** → **Rețea** (*Network*) →
  **Filtre** (*Filters*): selectează Little Snitch / LuLu și șterge-l.
- **Vrei ceva înapoi** — Finder → **Coș** → folderul „Firewall-uri eliminate …”,
  care păstrează căile originale (ex. `Library/Preferences/…`): trage
  elementul înapoi la locul lui. Aplicațiile duse la Coș de Finder au și
  opțiunea **Pune la loc** (clic dreapta).
- **Nu merge ceva** — trimite fișierul de log
  `~/Library/Logs/GDCFirewall-cleanup.log` (în Finder: meniul **Mergi →
  Mergi la dosarul…**, lipește calea, Enter).
