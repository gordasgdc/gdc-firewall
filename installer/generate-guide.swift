#!/usr/bin/env swift
// Generează installer/Instructiuni_Utilizare.pdf (RO/EN/ES) direct din cod:
// AppKit așază textul, Core Graphics scrie PDF-ul, PDFKit îl verifică la final
// (pagini, secțiuni obligatorii, orientare) — fără ca PDF-ul să fie citit de om.
//
// Rulează:  swift installer/generate-guide.swift
//
// Etichetele din ghid sunt EXACT textele din interfață (vezi GDC.strings): un
// ghid care numește un buton altfel decât îl vede utilizatorul îl pierde.
import AppKit
import PDFKit

// MARK: - Conținut

enum Block {
    case alert(String)        // casetă roșie, pentru pasul fără de care nimic nu merge
    case note(String)         // casetă caldă, explicații
    case steps([String])      // pași numerotați
    case bullets([String])
    case text(String)
}

struct Section {
    let heading: String
    let body: Block
    var critical = false
}

struct Guide {
    let language: String
    let subtitle: String
    let sections: [Section]
    let footer: String
}

let ro = Guide(
    language: "ro",
    subtitle: "Ghid de instalare și utilizare — Română",
    sections: [
        Section(heading: "0. PASUL CRITIC — Aprobarea extensiei de rețea", body: .alert(
            "Până când nu faci acest pas, GDC Firewall NU blochează nimic. Aplicația pornește, meniul funcționează, dar filtrul este oprit. Este singurul pas pe care macOS nu îl poate face în locul tău."), critical: true),
        Section(heading: "Cum aprobi extensia, pas cu pas", body: .steps([
            "Pornește GDC Firewall din Aplicații. macOS afișează fereastra <b>„Extensie de sistem blocată”</b>. Apasă <b>„Deschide Setări de sistem”</b>. Dacă ai închis-o din greșeală, deschide singur <b>Setări de sistem → General → Elemente de conectare și extensii</b>.",
            "Caută secțiunea <b>Extensii de rețea</b> și apasă butonul <b>(i)</b> din dreapta ei.",
            "Pornește comutatorul din dreptul <b>GDC Firewall</b>, apoi apasă <b>Gata</b>.",
            "macOS îți cere parola de administrator a Mac-ului (parola cu care te loghezi). Scrie-o și apasă Enter. Parola nu se vede pe ecran cât o tastezi — e normal.",
            "La întrebarea <b>„GDC Firewall ar dori să filtreze conținutul de rețea”</b> apasă <b>Permite</b>.",
            "Verifică: pictograma GDC Firewall din bara de sus trebuie să arate <b>„Protecție activă”</b>. Dacă arată <b>„Aprobă extensia în Setări de sistem”</b>, reia pașii 2–3.",
        ])),
        Section(heading: "De ce cere macOS asta", body: .note(
            "Un firewall trebuie să vadă fiecare conexiune de rețea a fiecărei aplicații. Apple nu permite niciunui program să facă asta fără acordul tău explicit, dat o singură dată, din Setări de sistem. Este o protecție pentru tine, nu o problemă a aplicației.")),
        Section(heading: "1. Instalare", body: .steps([
            "Descarcă arhiva de pe <b>gordas.dev/gdc-firewall</b> și deschide-o. Conține trei fișiere: aplicația <b>GDC Firewall</b>, scriptul de dezinstalare și acest ghid.",
            "Dă dublu-click pe <b>GDC Firewall</b>. Dacă aplicația nu e în folderul Aplicații, te întreabă dacă o mută acolo: apasă <b>„Mută în folderul Aplicații”</b>: se mută și repornește singură. E obligatoriu — macOS pornește filtrul de rețea doar din folderul Aplicații.",
            "Fă pasul 0 de mai sus.",
        ])),
        Section(heading: "2. Configurare inițială — alte firewall-uri și importul regulilor", body: .text(
            "Dacă pe Mac mai ai un firewall — <b>Little Snitch</b> sau <b>LuLu</b> — la prima pornire se deschide fereastra <b>„Configurare inițială”</b>. Două firewall-uri active îți cer permisiune de două ori pentru aceeași conexiune, deci merită să rămână unul singur. Dacă nu ai alt firewall, fereastra nu apare deloc. O poți redeschide oricând din meniu: <b>„Importă reguli din alte firewall-uri…”</b>.")),
        Section(heading: "Ce vezi în fereastră", body: .bullets([
            "Câte un card pentru fiecare firewall găsit, cu starea lui reală: <b>„Activ — filtrează conexiunile acum”</b>, <b>„Instalat, dar neaprobat în Setări”</b> sau doar reguli rămase pe disc.",
            "Butonul <b>„Importă regulile”</b> preia în GDC Firewall regulile pe care le-ai creat tu în acel firewall.",
            "Butonul <b>„Cum îl opresc”</b> arată pașii exacți pentru a-l opri și butoanele care deschid aplicația lui sau <b>Setări → Rețea</b>.",
        ])),
        Section(heading: "Importul din LuLu", body: .steps([
            "Apasă <b>„Importă regulile”</b> pe cardul LuLu. Nu ți se cere nicio parolă.",
            "GDC Firewall preia doar regulile create de tine. Sare peste cele dezactivate, expirate, valabile doar cât rula un program și peste regulile aplicațiilor care nu mai există pe Mac.",
            "Sub card apare rezultatul, de exemplu <b>„Importate: 100 · Existau deja: 13 · Sărite: aplicații absente pe acest Mac (107)”</b>. Poți apăsa din nou fără grijă: ce există deja nu se dublează.",
        ])),
        Section(heading: "Importul din Little Snitch", body: .steps([
            "Apasă <b>„Importă regulile”</b> pe cardul Little Snitch.",
            "macOS îți cere parola de administrator: Little Snitch își dă regulile doar unui administrator. Scrie parola (nu se vede cât tastezi) și apasă Enter.",
            "Dacă nu vrei să dai parola, deschide pașii <b>„Export manual, pas cu pas”</b>: în Little Snitch, meniul <b>File → Export Model…</b> salvează regulile într-un fișier. Apoi apasă <b>„Importă din fișier…”</b> și alege-l. La fel pentru LuLu: <b>Rules → Export</b>. Fișierele <b>.json</b>, <b>.lsrules</b> și <b>.plist</b> se recunosc automat.",
            "Unele reguli Little Snitch nu au echivalent în GDC Firewall: conexiunile de intrare, regulile „întreabă”, intervalele de porturi sau de adrese și destinațiile speciale (rețeaua locală, Bonjour). Acestea sunt sărite și numărate în rezultat — nicio regulă nu devine mai largă decât era.",
        ])),
        Section(heading: "Oprirea celuilalt firewall", body: .note(
            "macOS nu permite unei aplicații să oprească firewall-ul altui producător — pasul acesta îl faci tu, din aplicația lui. Apasă <b>„Cum îl opresc”</b>: pentru Little Snitch, comutatorul <b>„Network Filter”</b> pe Off; pentru LuLu, <b>Preferences → Disable</b>, sau <b>Setări de sistem → Rețea → Filtre</b>. Când ai terminat, apasă <b>„Gata”</b>.")),
        Section(heading: "3. Sistemul Semafor — ce înseamnă culorile", body: .bullets([
            "<b>Verde — Sigur.</b> Programul face parte din macOS și e semnat oficial de Apple. Recomandarea este <b>„Aprobă (Recomandat)”</b>. Blocarea lui poate strica funcții ale sistemului (iCloud, imprimante, notificări).",
            "<b>Galben — Aplicație cunoscută.</b> Programul e semnat de un dezvoltator identificat, dar nu face parte din macOS. Recomandarea este <b>„Verifică aplicația”</b> — aprob-o doar dacă o recunoști.",
            "<b>Roșu — Neidentificat.</b> Nu se știe cine a scris programul. Recomandarea este <b>„Blochează accesul”</b>. Dacă nu l-ai instalat tu conștient, blochează-l.",
        ])),
        Section(heading: "Cum răspunzi la o alertă", body: .steps([
            "Citește numele scris mare — e numele pe înțelesul tuturor, nu numele tehnic.",
            "Uită-te la insigna colorată și la recomandarea de sub butoane.",
            "Lasă bifat <b>„Ține minte alegerea pentru această aplicație”</b> ca răspunsul să devină o regulă permanentă. Debifează-l ca să decizi doar de data asta.",
            "Apasă <b>„Permite”</b> sau <b>„Blochează”</b>. Fereastra nu se închide altfel — conexiunea chiar așteaptă răspunsul tău.",
        ])),
        Section(heading: "4. Meniul din bara de sus", body: .bullets([
            "<b>„Protecție activă”</b> — totul funcționează.",
            "<b>„Filtrare oprită”</b> — ai oprit filtrarea. O pornești din comutatorul <b>„Filtrare activă”</b>, chiar sub acest mesaj.",
            "<b>„Aprobă extensia în Setări de sistem”</b> — pasul 0 nu e terminat.",
            "<b>„Se reconectează la motor…”</b> — legătura dintre aplicație și filtru se reface singură, de obicei în câteva secunde. Regulile tale se aplică în continuare.",
            "<b>„Actualizarea motorului e amânată”</b> — ai instalat o versiune nouă peste una care rula și ai apăsat „Anulează” la parola de administrator. Aplicația folosește în continuare filtrul vechi, deci ești protejat. Apasă <b>„Finalizează actualizarea motorului…”</b> din meniu și scrie parola (nu se vede cât tastezi): filtrul vechi se oprește, iar cel nou pornește în câteva secunde, fără repornirea Mac-ului.",
            "<b>„Repornește Mac-ul pentru a finaliza actualizarea”</b> — rar, după o actualizare făcută de o versiune mai veche a aplicației. Regulile tale se aplică în continuare; repornește Mac-ul când poți.",
        ])),
        Section(heading: "5. Modul Silențios (Aprobare inteligentă)", body: .note(
            "Este pornit din prima clipă. Aprobă automat, fără să te întrebe, doar componentele semnate oficial de Apple — altfel ai primi zeci de întrebări în prima oră. Tot ce NU e Apple te întreabă în continuare, de fiecare dată. Ce a aprobat singur vezi în <b>Setări → General → Aprobate automat</b>; tot de acolo îl poți opri.")),
        Section(heading: "6. Fereastra Reguli", body: .bullets([
            "Se deschide din meniu: <b>„Reguli…”</b>. Are trei părți: bara laterală din stânga, tabelul din mijloc și panoul de detalii din dreapta (butonul <b>Inspector</b> îl arată sau îl ascunde). Fereastra și fiecare parte se pot lărgi sau îngusta trăgând de margini.",
            "<b>Reguli</b>: <b>Toate regulile</b>, <b>Active</b>, <b>Blocate</b>, <b>Schimbări recente</b> (ultimele 7 zile), <b>Temporare</b> și <b>Neaprobate</b> — regulile create automat cât interfața nu era pornită, cu un număr roșu lângă ele. Butonul <b>„Aprobă toate”</b> le transformă în regulile tale.",
            "<b>Grupuri de reguli</b>: <b>Servicii iCloud</b>, <b>Servicii macOS</b>, <b>Aplicații Apple</b>, <b>Aplicații terțe</b>. Comutatorul de lângă fiecare grup îl activează sau îl dezactivează în întregime; clic dreapta pe grup: Editează, Exportă regulile…, Activează/Dezactivează grupul, Șterge….",
            "<b>Sugestii</b> și <b>Mentenanță</b>: reguli <b>Expirate</b>, <b>Redundante</b> (dublate), cu <b>Identitate schimbată</b> (programul de pe disc nu mai e cel aprobat), <b>Fără verificare de identitate</b> (programe nesemnate) și cu <b>Executabil lipsă</b>.",
            "Tabelul arată pictograma aplicației, numele ei, starea (<b>Permis</b>, <b>Blocat</b> sau <b>Dezactivată</b>) și destinația. Clic pe titlul unei coloane sortează; câmpul de căutare filtrează după proces, cale sau destinație.",
            "Clic dreapta pe o regulă: <b>Regulă nouă pentru „…”</b>, <b>Duplică</b>, <b>Editează regula…</b>, <b>Transformă în regulă globală</b>, <b>Activează/Dezactivează</b>, <b>Copiază regula / calea / domeniile</b>, <b>Arată în Finder</b>, <b>Repară calea procesului…</b> (dacă programul a fost mutat), <b>Arată doar regulile pentru „…”</b>, <b>Exportă…</b>, <b>Șterge</b>. Dublu-clic deschide editorul.",
            "Panoul de detalii arată calea, identitatea (ID cod, Team ID, cine a semnat și dacă semnătura de pe disc mai corespunde), proprietarul, data creării și de unde vine regula. Dacă programul nu mai există, apare un avertisment cu butonul <b>„Repară calea…”</b>.",
        ])),
        Section(heading: "7. Blocklist StevenBlack", body: .bullets([
            "Se configurează din bara laterală a ferestrei Reguli → <b>Blocklist-uri</b> → <b>StevenBlack</b>, din meniul <b>Blocklist</b> din bara de sus sau din <b>Setări → Filtrare &amp; AdBlock</b>.",
            "Comutatorul <b>„Blocklist StevenBlack”</b> îl pornește sau îl oprește; alături vezi câte domenii sunt blocate și butonul <b>„Actualizează acum”</b>.",
            "Baza <b>Unified</b> (reclame, malware, urmărire) e mereu inclusă. Peste ea poți bifa niveluri: <b>+Știri false</b>, <b>+Jocuri de noroc</b>, <b>+Pornografie</b>, <b>+Rețele sociale</b>. Listele bifate se îmbină automat într-una singură, fără dubluri.",
            "<b>Adaugă blocklist…</b> adaugă o listă publică proprie (adresă web a unui fișier hosts sau cu un domeniu pe linie); se îmbină și ea la fiecare actualizare.",
            "<b>Verifică un domeniu</b> îți spune dacă un site e pe listă; <b>„Permite acest domeniu”</b> îl trece la <b>Excepții</b>, care au mereu prioritate.",
            "Blocarea o face motorul de filtrare, pentru fiecare conexiune a fiecărei aplicații — inclusiv a celor pe care le-ai permis deja. Listele se descarcă din proiectul public StevenBlack/hosts și rămân pe Mac-ul tău.",
        ])),
        Section(heading: "8. Limba și aspectul", body: .text(
            "Aplicația vorbește română, engleză și spaniolă. Implicit urmează limba Mac-ului; în <b>Setări → General → Limbă</b> poți alege una anume. Tot acolo, <b>Temă</b> alege între Sistem, Light și Dark. Ambele se aplică imediat, fără repornire.")),
        Section(heading: "9. Actualizarea", body: .note(
            "Aplicația verifică actualizările la fiecare pornire. Fereastra are două butoane: <b>„Actualizează acum”</b> descarcă și instalează singur noua versiune — îți cere parola de administrator, apoi aplicația repornește; <b>„Mai târziu”</b> o închide până la versiunea următoare. Nu e o actualizare silențioasă în fundal: tu decizi când se întâmplă.<br/><br/>Există și fereastra <b>„Actualizare critică de securitate”</b>, când motorul de filtrare nu mai e susținut. Aceea nu are „Mai târziu” și reapare la fiecare pornire. Actualizarea automată înlocuiește și filtrul, cu aceeași parolă, fără repornirea Mac-ului. Dacă instalezi manual o versiune nouă peste una care rulează, aplicația îți cere o singură dată parola de administrator, ca să oprească filtrul vechi înainte să-l pornească pe cel nou.")),
        Section(heading: "10. Dezinstalare", body: .steps([
            "Din arhiva descărcată, dă dublu-click pe <b>Dezinstalare_GDCFirewall.command</b>.",
            "Scriptul îți cere parola de administrator a Mac-ului (nu se vede cât tastezi; apasă Enter), apoi macOS o poate cere încă o dată, într-o fereastră, pentru oprirea filtrului de rețea.",
            "Funcționează oriunde s-ar afla aplicația — în Aplicații, în Descărcări sau redenumită — și scoate tot: filtrul de rețea, regulile, preferințele, logurile și toate copiile aplicației. La final îți arată ce a verificat.",
            "Dacă la final scrie că filtrul se elimină la repornire, repornește Mac-ul când poți. Un LuLu sau Little Snitch instalat separat rămâne neatins.",
        ])),
        Section(heading: "11. Susținere și licență", body: .note(
            "GDC Firewall este gratuit și rămâne gratuit. Dacă îți este de folos, o donație de <b>23 €</b> acoperă timpul de întreținere și taxele de dezvoltator Apple. Donația e opțională și nu deblochează nimic — toate funcțiile sunt deja disponibile.<br/><br/>Aplicația este distribuită sub licența GPL-3.0, cu sursa publică. Motorul de filtrare este LuLu, © Objective-See.")),
    ],
    footer: "GDC Firewall — gordas.dev/gdc-firewall · © 2026 Cristi Gordaș / GDC · GPL-3.0 · Motor: LuLu © Objective-See"
)

let en = Guide(
    language: "en",
    subtitle: "Installation and user guide — English",
    sections: [
        Section(heading: "0. CRITICAL STEP — Approving the network extension", body: .alert(
            "Until you complete this step, GDC Firewall blocks NOTHING. The app starts, the menu works, but the filter is off. This is the one step macOS cannot do for you."), critical: true),
        Section(heading: "Approving the extension, step by step", body: .steps([
            "Launch GDC Firewall from Applications. macOS shows the <b>“System Extension Blocked”</b> window. Click <b>“Open System Settings”</b>. If you closed it by accident, open <b>System Settings → General → Login Items &amp; Extensions</b> yourself.",
            "Find the <b>Network Extensions</b> section and click the <b>(i)</b> button next to it.",
            "Turn on the switch for <b>GDC Firewall</b>, then click <b>Done</b>.",
            "macOS asks for your Mac administrator password (the one you log in with). Type it and press Enter. The password stays invisible while you type — that is normal.",
            "When asked <b>“GDC Firewall would like to filter network content”</b>, click <b>Allow</b>.",
            "Check: the GDC Firewall icon in the menu bar should read <b>“Protection on”</b>. If it reads <b>“Approve the extension in System Settings”</b>, repeat steps 2–3.",
        ])),
        Section(heading: "Why macOS asks for this", body: .note(
            "A firewall has to see every network connection of every app. Apple does not let any program do that without your explicit consent, given once, in System Settings. It protects you; it is not a fault of the app.")),
        Section(heading: "1. Installation", body: .steps([
            "Download the archive from <b>gordas.dev/gdc-firewall</b> and open it. It holds three files: the <b>GDC Firewall</b> app, the uninstall script and this guide.",
            "Double-click <b>GDC Firewall</b>. If the app is not in your Applications folder, it offers to move itself there: click <b>“Move to Applications Folder”</b>: it moves itself and relaunches. This is required — macOS only starts the network filter from the Applications folder.",
            "Complete step 0 above.",
        ])),
        Section(heading: "2. Initial setup — other firewalls and importing rules", body: .text(
            "If your Mac already has a firewall — <b>Little Snitch</b> or <b>LuLu</b> — the <b>“Initial setup”</b> window opens on first launch. Two active firewalls ask you twice about the same connection, so it is worth keeping just one. If you have no other firewall, the window never appears. You can reopen it any time from the menu: <b>“Import rules from other firewalls…”</b>.")),
        Section(heading: "What the window shows", body: .bullets([
            "One card for each firewall found, with its real state: <b>“Active — filtering connections now”</b>, <b>“Installed, but not approved in Settings”</b>, or only leftover rules on disk.",
            "<b>“Import rules”</b> brings into GDC Firewall the rules you created in that firewall.",
            "<b>“How to turn it off”</b> shows the exact steps, plus buttons that open its app or <b>Settings → Network</b>.",
        ])),
        Section(heading: "Importing from LuLu", body: .steps([
            "Click <b>“Import rules”</b> on the LuLu card. No password is needed.",
            "GDC Firewall takes only the rules you created. It skips disabled and expired rules, rules that were valid only while a program ran, and rules for apps that are no longer on your Mac.",
            "The result appears under the card, for example <b>“Imported: 100 · Already present: 13 · Skipped: apps missing from this Mac (107)”</b>. Clicking again is safe: nothing is duplicated.",
        ])),
        Section(heading: "Importing from Little Snitch", body: .steps([
            "Click <b>“Import rules”</b> on the Little Snitch card.",
            "macOS asks for your administrator password: Little Snitch hands its rules only to an administrator. Type it (it stays invisible) and press Enter.",
            "If you prefer not to enter the password, open <b>“Manual export, step by step”</b>: in Little Snitch, the <b>File → Export Model…</b> menu saves the rules to a file. Then click <b>“Import from File…”</b> and choose it. The same works for LuLu: <b>Rules → Export</b>. <b>.json</b>, <b>.lsrules</b> and <b>.plist</b> files are recognized automatically.",
            "Some Little Snitch rules have no equivalent in GDC Firewall: incoming connections, “ask” rules, port or address ranges, and special destinations (local network, Bonjour). They are skipped and counted in the result — no rule ever becomes broader than it was.",
        ])),
        Section(heading: "Turning the other firewall off", body: .note(
            "macOS does not let one app turn off another vendor's firewall — you do this step yourself, from that firewall's own app. Click <b>“How to turn it off”</b>: for Little Snitch, set the <b>“Network Filter”</b> switch to Off; for LuLu, <b>Preferences → Disable</b>, or <b>System Settings → Network → Filters</b>. When you are done, click <b>“Done”</b>.")),
        Section(heading: "3. The traffic-light system", body: .bullets([
            "<b>Green — Safe.</b> The program is part of macOS and officially signed by Apple. The recommendation is <b>“Allow (Recommended)”</b>. Blocking it may break system features (iCloud, printers, notifications).",
            "<b>Yellow — Known app.</b> Signed by an identified developer, but not part of macOS. The recommendation is <b>“Check the app”</b> — allow it only if you recognize it.",
            "<b>Red — Unidentified.</b> Nobody knows who wrote this program. The recommendation is <b>“Block access”</b>. If you did not install it knowingly, block it.",
        ])),
        Section(heading: "Answering an alert", body: .steps([
            "Read the large name — it is the plain-language name, not the technical one.",
            "Look at the colored badge and at the recommendation under the buttons.",
            "Leave <b>“Remember my choice for this app”</b> ticked to turn your answer into a permanent rule. Untick it to decide just this once.",
            "Click <b>“Allow”</b> or <b>“Block”</b>. The window closes no other way — a real connection is waiting for your answer.",
        ])),
        Section(heading: "4. The menu bar menu", body: .bullets([
            "<b>“Protection on”</b> — everything works.",
            "<b>“Filtering off”</b> — you turned filtering off. Turn it back on with the <b>“Filtering on”</b> switch right below.",
            "<b>“Approve the extension in System Settings”</b> — step 0 is not finished.",
            "<b>“Reconnecting to the engine…”</b> — the link between the app and the filter restores itself, usually within a few seconds. Your rules still apply.",
            "<b>“Engine update postponed”</b> — you installed a new version over a running one and clicked “Cancel” at the administrator password. The app keeps using the old filter, so you are protected. Click <b>“Finish Engine Update…”</b> in the menu and type your password (it stays invisible while you type): the old filter stops and the new one starts within seconds, without restarting your Mac.",
            "<b>“Restart your Mac to finish the update”</b> — rare, after an update made by an older version of the app. Your rules still apply; restart your Mac when convenient.",
        ])),
        Section(heading: "5. Silent Mode (smart approval)", body: .note(
            "It is on from the very first launch. It silently allows only components officially signed by Apple — otherwise you would face dozens of prompts in the first hour. Anything not from Apple still asks you, every time. Whatever it approved on its own is listed under <b>Settings → General → Approved automatically</b>, where you can also turn it off.")),
        Section(heading: "6. The Rules window", body: .bullets([
            "Open it from the menu: <b>“Rules…”</b>. It has three parts: the sidebar on the left, the table in the middle and the details panel on the right (the <b>Inspector</b> button shows or hides it). The window and each part can be widened or narrowed by dragging their edges.",
            "<b>Rules</b>: <b>All Rules</b>, <b>Active</b>, <b>Deny</b>, <b>Recent Changes</b> (last 7 days), <b>Temporary</b> and <b>Unapproved</b> — rules created automatically while the interface wasn't running, with a red count next to them. The <b>“Approve All”</b> button turns them into your own rules.",
            "<b>Rule Groups</b>: <b>iCloud Services</b>, <b>macOS Services</b>, <b>Apple Apps</b>, <b>Third-Party Apps</b>. The switch next to each group enables or disables it as a whole; right-click a group for Edit, Export Rules…, Enable/Disable Group, Delete….",
            "<b>Suggestions</b> and <b>Maintenance</b>: <b>Expired</b>, <b>Redundant</b> (duplicated) rules, <b>Identity Mismatch</b> (the program on disk is no longer the approved one), <b>No Identity Check</b> (unsigned programs) and <b>Missing Executable</b>.",
            "The table shows the app icon, its name, the status (<b>Allowed</b>, <b>Blocked</b> or <b>Disabled</b>) and the destination. Click a column title to sort; the search field filters by process, path or destination.",
            "Right-click a rule: <b>New Rule for “…”</b>, <b>Duplicate</b>, <b>Edit Rule…</b>, <b>Turn into Global Rule</b>, <b>Enable/Disable</b>, <b>Copy Rule / Process Path / Domains</b>, <b>Show in Finder</b>, <b>Repair Process Path…</b> (if the program was moved), <b>Focus on Rules Affecting “…”</b>, <b>Export…</b>, <b>Delete</b>. Double-click opens the editor.",
            "The details panel shows the path, the identity (Code ID, Team ID, who signed it and whether the signature on disk still matches), the owner, the creation date and where the rule came from. If the program no longer exists, a warning appears with a <b>“Repair Path…”</b> button.",
        ])),
        Section(heading: "7. StevenBlack blocklist", body: .bullets([
            "Configure it from the Rules window sidebar → <b>Blocklists</b> → <b>StevenBlack</b>, from the <b>Blocklist</b> menu in the menu bar, or from <b>Settings → Filtering &amp; AdBlock</b>.",
            "The <b>“StevenBlack blocklist”</b> switch turns it on or off; next to it you see how many domains are blocked and the <b>“Update now”</b> button.",
            "The <b>Unified</b> base (ads, malware, tracking) is always included. On top of it you can tick levels: <b>+Fake news</b>, <b>+Gambling</b>, <b>+Porn</b>, <b>+Social media</b>. The ticked lists are merged automatically into one, without duplicates.",
            "<b>Add blocklist…</b> adds a public list of your own (the web address of a hosts file or of a list with one domain per line); it is merged on every update too.",
            "<b>Check a domain</b> tells you whether a site is on the list; <b>“Allow this domain”</b> moves it to <b>Exceptions</b>, which always win.",
            "Blocking is done by the filtering engine, for every connection of every app — including apps you have already allowed. The lists are downloaded from the public StevenBlack/hosts project and stay on your Mac.",
        ])),
        Section(heading: "8. Language and appearance", body: .text(
            "The app speaks Romanian, English and Spanish. By default it follows your Mac's language; in <b>Settings → General → Language</b> you can pick one. In the same place, <b>Theme</b> chooses between System, Light and Dark. Both apply immediately, without a restart.")),
        Section(heading: "9. Updates", body: .note(
            "The app checks for updates at every launch. The window has two buttons: <b>“Update now”</b> downloads and installs the new version for you — it asks for your administrator password, then the app restarts; <b>“Later”</b> dismisses it until the next version. This is not a silent background update: you decide when it happens.<br/><br/>There is also a <b>“Critical security update”</b> window, shown when the filtering engine is no longer supported. That one has no “Later” and returns at every launch. The automatic update also replaces the filter, with the same password, without restarting your Mac. If you install a new version manually over a running one, the app asks for your administrator password once, to stop the old filter before starting the new one.")),
        Section(heading: "10. Uninstalling", body: .steps([
            "From the downloaded archive, double-click <b>Dezinstalare_GDCFirewall.command</b>.",
            "The script asks for your Mac's administrator password (invisible while you type; press Enter); macOS may ask once more, in a window, to stop the network filter.",
            "It works wherever the app is — in Applications, in Downloads or renamed — and removes everything: the network filter, rules, preferences, logs and every copy of the app. At the end it shows what it checked.",
            "If it says the filter is removed at the next restart, restart your Mac when convenient. A separately installed LuLu or Little Snitch is left untouched.",
        ])),
        Section(heading: "11. Support and license", body: .note(
            "GDC Firewall is free and stays free. If you find it useful, a <b>€23</b> donation covers maintenance time and Apple developer fees. The donation is optional and unlocks nothing — every feature is already available.<br/><br/>The app is distributed under the GPL-3.0 license, with public source code. The filtering engine is LuLu, © Objective-See.")),
    ],
    footer: "GDC Firewall — gordas.dev/gdc-firewall · © 2026 Cristi Gordaș / GDC · GPL-3.0 · Engine: LuLu © Objective-See"
)

let es = Guide(
    language: "es",
    subtitle: "Guía de instalación y uso — Español",
    sections: [
        Section(heading: "0. PASO CRÍTICO — Aprobar la extensión de red", body: .alert(
            "Hasta que completes este paso, GDC Firewall NO bloquea NADA. La app se abre, el menú funciona, pero el filtro está apagado. Es el único paso que macOS no puede hacer por ti."), critical: true),
        Section(heading: "Cómo aprobar la extensión, paso a paso", body: .steps([
            "Abre GDC Firewall desde Aplicaciones. macOS muestra la ventana <b>«Extensión del sistema bloqueada»</b>. Pulsa <b>«Abrir Ajustes del Sistema»</b>. Si la cerraste sin querer, abre tú mismo <b>Ajustes del Sistema → General → Ítems de inicio y extensiones</b>.",
            "Busca la sección <b>Extensiones de red</b> y pulsa el botón <b>(i)</b> que está a su lado.",
            "Activa el interruptor de <b>GDC Firewall</b> y pulsa <b>Listo</b>.",
            "macOS te pide la contraseña de administrador del Mac (la que usas para iniciar sesión). Escríbela y pulsa Intro. La contraseña no se ve mientras la escribes: es normal.",
            "Cuando pregunte <b>«GDC Firewall quiere filtrar el contenido de red»</b>, pulsa <b>Permitir</b>.",
            "Comprueba: el icono de GDC Firewall en la barra de menús debe indicar <b>«Protección activa»</b>. Si indica <b>«Aprueba la extensión en Ajustes del Sistema»</b>, repite los pasos 2 y 3.",
        ])),
        Section(heading: "Por qué macOS pide esto", body: .note(
            "Un firewall necesita ver cada conexión de red de cada app. Apple no permite que ningún programa haga eso sin tu consentimiento explícito, dado una sola vez, en Ajustes del Sistema. Es una protección para ti, no un fallo de la app.")),
        Section(heading: "1. Instalación", body: .steps([
            "Descarga el archivo comprimido desde <b>gordas.dev/gdc-firewall</b> y ábrelo. Contiene tres archivos: la app <b>GDC Firewall</b>, el script de desinstalación y esta guía.",
            "Haz doble clic en <b>GDC Firewall</b>. Si la app no está en la carpeta Aplicaciones, te ofrece moverse allí: pulsa <b>«Mover a la carpeta Aplicaciones»</b>: se mueve y se reinicia sola. Es obligatorio: macOS solo inicia el filtro de red desde la carpeta Aplicaciones.",
            "Completa el paso 0 anterior.",
        ])),
        Section(heading: "2. Configuración inicial — otros firewalls e importación de reglas", body: .text(
            "Si tu Mac ya tiene un firewall — <b>Little Snitch</b> o <b>LuLu</b> —, la primera vez se abre la ventana <b>«Configuración inicial»</b>. Dos firewalls activos te piden permiso dos veces para la misma conexión, así que conviene quedarse con uno solo. Si no tienes otro firewall, la ventana no aparece. Puedes volver a abrirla desde el menú: <b>«Importar reglas de otros firewalls…»</b>.")),
        Section(heading: "Qué muestra la ventana", body: .bullets([
            "Una tarjeta por cada firewall encontrado, con su estado real: <b>«Activo — filtra las conexiones ahora»</b>, <b>«Instalado, pero no aprobado en Ajustes»</b> o solo reglas que quedan en el disco.",
            "<b>«Importar reglas»</b> trae a GDC Firewall las reglas que creaste en ese firewall.",
            "<b>«Cómo desactivarlo»</b> muestra los pasos exactos y botones que abren su app o <b>Ajustes → Red</b>.",
        ])),
        Section(heading: "Importar desde LuLu", body: .steps([
            "Pulsa <b>«Importar reglas»</b> en la tarjeta de LuLu. No se pide contraseña.",
            "GDC Firewall toma solo las reglas que creaste tú. Omite las desactivadas, las caducadas, las que valían solo mientras se ejecutaba un programa y las de apps que ya no están en el Mac.",
            "El resultado aparece bajo la tarjeta, por ejemplo <b>«Importadas: 100 · Ya existían: 13 · Omitidas: apps que no están en este Mac (107)»</b>. Puedes volver a pulsar sin miedo: nada se duplica.",
        ])),
        Section(heading: "Importar desde Little Snitch", body: .steps([
            "Pulsa <b>«Importar reglas»</b> en la tarjeta de Little Snitch.",
            "macOS te pide la contraseña de administrador: Little Snitch solo entrega sus reglas a un administrador. Escríbela (no se ve) y pulsa Intro.",
            "Si prefieres no dar la contraseña, abre <b>«Exportación manual, paso a paso»</b>: en Little Snitch, el menú <b>File → Export Model…</b> guarda las reglas en un archivo. Luego pulsa <b>«Importar desde archivo…»</b> y elígelo. Lo mismo para LuLu: <b>Rules → Export</b>. Los archivos <b>.json</b>, <b>.lsrules</b> y <b>.plist</b> se reconocen automáticamente.",
            "Algunas reglas de Little Snitch no tienen equivalente en GDC Firewall: conexiones entrantes, reglas «preguntar», rangos de puertos o de direcciones y destinos especiales (red local, Bonjour). Se omiten y se cuentan en el resultado: ninguna regla se vuelve más amplia de lo que era.",
        ])),
        Section(heading: "Desactivar el otro firewall", body: .note(
            "macOS no permite que una app desactive el firewall de otro fabricante: este paso lo haces tú, desde su propia app. Pulsa <b>«Cómo desactivarlo»</b>: en Little Snitch, pon el interruptor <b>«Network Filter»</b> en Off; en LuLu, <b>Preferences → Disable</b>, o <b>Ajustes del Sistema → Red → Filtros</b>. Cuando termines, pulsa <b>«Listo»</b>.")),
        Section(heading: "3. El sistema de semáforo", body: .bullets([
            "<b>Verde — Seguro.</b> El programa forma parte de macOS y está firmado oficialmente por Apple. La recomendación es <b>«Aprobar (Recomendado)»</b>. Bloquearlo puede estropear funciones del sistema (iCloud, impresoras, notificaciones).",
            "<b>Amarillo — App conocida.</b> Firmada por un desarrollador identificado, pero no forma parte de macOS. La recomendación es <b>«Revisa la app»</b>: apruébala solo si la reconoces.",
            "<b>Rojo — No identificado.</b> No se sabe quién escribió este programa. La recomendación es <b>«Bloquear el acceso»</b>. Si no lo instalaste a sabiendas, bloquéalo.",
        ])),
        Section(heading: "Cómo responder a una alerta", body: .steps([
            "Lee el nombre grande: es el nombre en lenguaje sencillo, no el técnico.",
            "Fíjate en la insignia de color y en la recomendación bajo los botones.",
            "Deja marcado <b>«Recordar mi elección para esta app»</b> para que tu respuesta sea una regla permanente. Desmárcalo para decidir solo esta vez.",
            "Pulsa <b>«Permitir»</b> o <b>«Bloquear»</b>. La ventana no se cierra de otra forma: una conexión real espera tu respuesta.",
        ])),
        Section(heading: "4. El menú de la barra de menús", body: .bullets([
            "<b>«Protección activa»</b> — todo funciona.",
            "<b>«Filtrado desactivado»</b> — desactivaste el filtrado. Vuelve a activarlo con el interruptor <b>«Filtrado activo»</b>, justo debajo.",
            "<b>«Aprueba la extensión en Ajustes del Sistema»</b> — el paso 0 no está terminado.",
            "<b>«Reconectando con el motor…»</b> — la conexión entre la app y el filtro se restablece sola, normalmente en unos segundos. Tus reglas se siguen aplicando.",
            "<b>«Actualización del motor aplazada»</b> — instalaste una versión nueva sobre una que estaba en marcha y pulsaste «Cancelar» en la contraseña de administrador. La app sigue usando el filtro anterior, así que estás protegido. Pulsa <b>«Terminar la actualización del motor…»</b> en el menú y escribe la contraseña (no se ve mientras la escribes): el filtro anterior se detiene y el nuevo arranca en segundos, sin reiniciar el Mac.",
            "<b>«Reinicia el Mac para terminar la actualización»</b> — poco frecuente, tras una actualización hecha por una versión anterior de la app. Tus reglas se siguen aplicando; reinicia el Mac cuando puedas.",
        ])),
        Section(heading: "5. Modo silencioso (aprobación inteligente)", body: .note(
            "Está activado desde el primer momento. Aprueba en silencio solo los componentes firmados oficialmente por Apple; de lo contrario recibirías decenas de avisos en la primera hora. Todo lo que no sea de Apple te sigue preguntando, siempre. Lo que aprobó por su cuenta aparece en <b>Ajustes → General → Aprobados automáticamente</b>, donde también puedes desactivarlo.")),
        Section(heading: "6. La ventana Reglas", body: .bullets([
            "Se abre desde el menú: <b>«Reglas…»</b>. Tiene tres partes: la barra lateral a la izquierda, la tabla en el centro y el panel de detalles a la derecha (el botón <b>Inspector</b> lo muestra u oculta). La ventana y cada parte se pueden ensanchar o estrechar arrastrando sus bordes.",
            "<b>Reglas</b>: <b>Todas las reglas</b>, <b>Activas</b>, <b>Bloqueadas</b>, <b>Cambios recientes</b> (últimos 7 días), <b>Temporales</b> y <b>Sin aprobar</b>: reglas creadas automáticamente mientras la interfaz no estaba abierta, con un número rojo al lado. El botón <b>«Aprobar todas»</b> las convierte en tus reglas.",
            "<b>Grupos de reglas</b>: <b>Servicios de iCloud</b>, <b>Servicios de macOS</b>, <b>Apps de Apple</b>, <b>Apps de terceros</b>. El interruptor junto a cada grupo lo activa o desactiva por completo; con clic derecho en el grupo: Editar, Exportar reglas…, Activar/Desactivar grupo, Eliminar….",
            "<b>Sugerencias</b> y <b>Mantenimiento</b>: reglas <b>Caducadas</b>, <b>Redundantes</b> (duplicadas), con <b>Identidad distinta</b> (el programa en el disco ya no es el aprobado), <b>Sin comprobación de identidad</b> (programas sin firmar) y con <b>Ejecutable ausente</b>.",
            "La tabla muestra el icono de la app, su nombre, el estado (<b>Permitido</b>, <b>Bloqueado</b> o <b>Desactivada</b>) y el destino. Haz clic en el título de una columna para ordenar; el campo de búsqueda filtra por proceso, ruta o destino.",
            "Clic derecho en una regla: <b>Nueva regla para «…»</b>, <b>Duplicar</b>, <b>Editar regla…</b>, <b>Convertir en regla global</b>, <b>Activar/Desactivar</b>, <b>Copiar regla / ruta / dominios</b>, <b>Mostrar en el Finder</b>, <b>Reparar ruta del proceso…</b> (si el programa se movió), <b>Mostrar solo las reglas de «…»</b>, <b>Exportar…</b>, <b>Eliminar</b>. El doble clic abre el editor.",
            "El panel de detalles muestra la ruta, la identidad (ID de código, Team ID, quién la firmó y si la firma en el disco aún coincide), el propietario, la fecha de creación y el origen de la regla. Si el programa ya no existe, aparece un aviso con el botón <b>«Reparar ruta…»</b>.",
        ])),
        Section(heading: "7. Lista de bloqueo StevenBlack", body: .bullets([
            "Se configura desde la barra lateral de la ventana Reglas → <b>Listas de bloqueo</b> → <b>StevenBlack</b>, desde el menú <b>Lista de bloqueo</b> de la barra de menús o desde <b>Ajustes → Filtrado y AdBlock</b>.",
            "El interruptor <b>«Lista de bloqueo StevenBlack»</b> la activa o desactiva; al lado ves cuántos dominios están bloqueados y el botón <b>«Actualizar ahora»</b>.",
            "La base <b>Unified</b> (anuncios, malware, rastreo) siempre está incluida. Encima puedes marcar niveles: <b>+Noticias falsas</b>, <b>+Juegos de azar</b>, <b>+Pornografía</b>, <b>+Redes sociales</b>. Las listas marcadas se combinan automáticamente en una sola, sin duplicados.",
            "<b>Añadir lista de bloqueo…</b> añade una lista pública propia (la dirección web de un archivo hosts o de una lista con un dominio por línea); también se combina en cada actualización.",
            "<b>Comprobar un dominio</b> te dice si un sitio está en la lista; <b>«Permitir este dominio»</b> lo pasa a <b>Excepciones</b>, que siempre tienen prioridad.",
            "El bloqueo lo hace el motor de filtrado, para cada conexión de cada app, incluidas las que ya permitiste. Las listas se descargan del proyecto público StevenBlack/hosts y se quedan en tu Mac.",
        ])),
        Section(heading: "8. Idioma y apariencia", body: .text(
            "La app habla rumano, inglés y español. Por defecto sigue el idioma del Mac; en <b>Ajustes → General → Idioma</b> puedes elegir uno. En el mismo lugar, <b>Tema</b> elige entre Sistema, Claro y Oscuro. Ambos se aplican al instante, sin reiniciar.")),
        Section(heading: "9. Actualizaciones", body: .note(
            "La app busca actualizaciones en cada inicio. La ventana tiene dos botones: <b>«Actualizar ahora»</b> descarga e instala sola la nueva versión — te pide la contraseña de administrador y luego la app se reinicia; <b>«Más tarde»</b> la cierra hasta la siguiente versión. No es una actualización silenciosa en segundo plano: tú decides cuándo ocurre.<br/><br/>También existe la ventana <b>«Actualización de seguridad crítica»</b>, cuando el motor de filtrado ya no está soportado. Esa no tiene «Más tarde» y vuelve en cada inicio. La actualización automática también sustituye el filtro, con la misma contraseña y sin reiniciar el Mac. Si instalas manualmente una versión nueva sobre una que está en marcha, la app te pide una sola vez la contraseña de administrador, para detener el filtro anterior antes de iniciar el nuevo.")),
        Section(heading: "10. Desinstalación", body: .steps([
            "Desde el archivo descargado, haz doble clic en <b>Dezinstalare_GDCFirewall.command</b>.",
            "El script te pide la contraseña de administrador del Mac (no se ve mientras la escribes; pulsa Intro); macOS puede pedirla otra vez, en una ventana, para detener el filtro de red.",
            "Funciona esté donde esté la app —en Aplicaciones, en Descargas o con otro nombre— y lo elimina todo: el filtro de red, las reglas, las preferencias, los registros y todas las copias de la app. Al final muestra lo que ha comprobado.",
            "Si indica que el filtro se elimina en el próximo reinicio, reinicia el Mac cuando puedas. Un LuLu o Little Snitch instalado aparte no se toca.",
        ])),
        Section(heading: "11. Apoyo y licencia", body: .note(
            "GDC Firewall es gratuito y seguirá siéndolo. Si te resulta útil, una donación de <b>23 €</b> cubre el tiempo de mantenimiento y las cuotas de desarrollador de Apple. La donación es opcional y no desbloquea nada: todas las funciones ya están disponibles.<br/><br/>La app se distribuye bajo la licencia GPL-3.0, con código fuente público. El motor de filtrado es LuLu, © Objective-See.")),
    ],
    footer: "GDC Firewall — gordas.dev/gdc-firewall · © 2026 Cristi Gordaș / GDC · GPL-3.0 · Motor: LuLu © Objective-See"
)

let guides = [ro, en, es]

// MARK: - Reguli de conținut, verificate înainte de desenare

/// Regula 3: susținerea e donație, niciodată „preț”/„cumpără”/„vânzare”,
/// în nicio limbă.
/// Pe limite de cuvânt: „ventana” (ES, fereastră) conține „venta”.
let forbidden = try! NSRegularExpression(
    pattern: #"\b(preț|pret|prețul|cumpăr\w*|vânzare|vânzări|price[sd]?|buy|purchase\w*|sales?|precios?|compra\w*|ventas?)\b"#,
    options: [.caseInsensitive])
for guide in guides {
    var all = guide.subtitle + " " + guide.footer
    for section in guide.sections {
        all += " " + section.heading + " "
        switch section.body {
        case .alert(let t), .note(let t), .text(let t): all += t
        case .steps(let items), .bullets(let items): all += items.joined(separator: " ")
        }
    }
    if let hit = forbidden.firstMatch(in: all, range: NSRange(all.startIndex..., in: all)) {
        fatalError("Regula 3: cuvântul interzis „\((all as NSString).substring(with: hit.range))” apare în ghidul \(guide.language)")
    }
}

// MARK: - Aspect

let pageSize = CGSize(width: 595.28, height: 841.89)   // A4
let margin = (left: 50.0, right: 50.0, top: 46.0, bottom: 58.0)
let textSize = CGSize(width: pageSize.width - margin.left - margin.right,
                      height: pageSize.height - margin.top - margin.bottom)

func rgb(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let accent = rgb(0xC97D2E)
let ink = rgb(0x1A1A1A)
let muted = rgb(0x6A6A6A)
let noteBackground = rgb(0xFBF1E6)
let alertBackground = rgb(0xFDECEC)
let alertInk = rgb(0x8F2323)

func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
    bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
}

func paragraph(line: CGFloat = 15, indent: CGFloat = 0) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = line
    style.headIndent = indent
    if indent > 0 { style.tabStops = [NSTextTab(textAlignment: .left, location: indent)] }
    return style
}

/// Marcaj minimal: <b>…</b> pentru bold, <br/> pentru rând nou, &amp; pentru &.
func styled(_ markup: String, size: CGFloat, color: NSColor, style: NSParagraphStyle,
            allBold: Bool = false) -> NSAttributedString {
    let text = markup.replacingOccurrences(of: "<br/>", with: "\n")
                     .replacingOccurrences(of: "&amp;", with: "&")
    let out = NSMutableAttributedString()
    var bold = allBold
    var rest = Substring(text)
    while !rest.isEmpty {
        let tag = bold && !allBold ? "</b>" : "<b>"
        let range = rest.range(of: tag)
        let chunk = range.map { rest[..<$0.lowerBound] } ?? rest
        out.append(NSAttributedString(string: String(chunk), attributes: [
            .font: font(size, bold: bold), .foregroundColor: color, .paragraphStyle: style,
        ]))
        guard let range else { break }
        rest = rest[range.upperBound...]
        if !allBold { bold.toggle() }
    }
    return out
}

// MARK: - Așezare proprie
//
// Fără NSTextBlock și fără paginarea NSLayoutManager: o casetă care trebuie
// împărțită între pagini bagă motorul de text AppKit într-o buclă infinită
// (layoutRectForTextBlock). Aici fiecare paragraf e măsurat și pus întreg pe
// o pagină — paragrafele ghidului sunt scurte, deci încap mereu.

struct Item {
    let text: NSAttributedString
    var before: CGFloat = 0
    var after: CGFloat = 6
    var box: NSColor? = nil
    var keepWithNext = false
}

let boxPadding: CGFloat = 8

func height(of item: Item) -> CGFloat {
    let width = textSize.width - (item.box != nil ? 2 * boxPadding : 0)
    let rect = item.text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(rect.height) + (item.box != nil ? 2 * boxPadding : 0)
}

func items(for guide: Guide) -> [Item] {
    var list: [Item] = [
        Item(text: styled("GDC Firewall", size: 20, color: ink, style: paragraph(line: 24), allBold: true), after: 2),
        Item(text: styled(guide.subtitle, size: 11, color: muted, style: paragraph()), after: 14),
    ]
    for section in guide.sections {
        list.append(Item(text: styled(section.heading, size: 13, color: section.critical ? alertInk : accent,
                                      style: paragraph(line: 17), allBold: true),
                         before: 10, after: 5, keepWithNext: true))
        switch section.body {
        case .text(let t):
            list.append(Item(text: styled(t, size: 10.5, color: ink, style: paragraph())))
        case .alert(let t):
            list.append(Item(text: styled(t, size: 10.5, color: alertInk, style: paragraph(), allBold: true),
                             after: 8, box: alertBackground))
        case .note(let t):
            list.append(Item(text: styled(t, size: 10, color: ink, style: paragraph(line: 14)),
                             after: 8, box: noteBackground))
        case .steps(let steps):
            for (i, step) in steps.enumerated() {
                list.append(Item(text: styled("\(i + 1).\t" + step, size: 10.5, color: ink, style: paragraph(indent: 18)), after: 4))
            }
        case .bullets(let bullets):
            for bullet in bullets {
                list.append(Item(text: styled("•\t" + bullet, size: 10.5, color: ink, style: paragraph(indent: 18)), after: 4))
            }
        }
    }
    return list
}

/// Pagini = liste de (item, y). Un titlu trece pe pagina următoare dacă
/// primul paragraf de sub el nu încape lângă el.
func paginate(_ list: [Item]) -> [[(Item, CGFloat)]] {
    var pages: [[(Item, CGFloat)]] = [[]]
    var y: CGFloat = 0
    for (index, item) in list.enumerated() {
        let h = height(of: item)
        var needed = (pages[pages.count - 1].isEmpty ? 0 : item.before) + h
        if item.keepWithNext, index + 1 < list.count {
            needed += item.after + height(of: list[index + 1])
        }
        if y + needed > textSize.height, !pages[pages.count - 1].isEmpty {
            pages.append([])
            y = 0
        }
        if !pages[pages.count - 1].isEmpty { y += item.before }
        pages[pages.count - 1].append((item, y))
        y += h + item.after
    }
    return pages
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                 : URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Instructiuni_Utilizare.pdf").path)
var mediaBox = CGRect(origin: .zero, size: pageSize)
let info: [CFString: Any] = [
    kCGPDFContextTitle: "GDC Firewall — Instrucțiuni de utilizare",
    kCGPDFContextAuthor: "Cristi Gordaș / GDC",
    kCGPDFContextCreator: "installer/generate-guide.swift",
]
guard let pdf = CGContext(output as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
    fatalError("Nu pot crea \(output.path)")
}

var pageNumber = 0
for guide in guides {
    for page in paginate(items(for: guide)) {
        pageNumber += 1
        pdf.beginPDFPage(nil)
        pdf.saveGState()
        // Coordonate de sus în jos, ca la citire.
        pdf.translateBy(x: 0, y: pageSize.height)
        pdf.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)

        for (item, y) in page {
            let h = height(of: item)
            var rect = CGRect(x: margin.left, y: margin.top + y, width: textSize.width, height: h)
            if let color = item.box {
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
                rect = rect.insetBy(dx: boxPadding, dy: boxPadding)
            }
            item.text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        let footer = NSAttributedString(string: "\(guide.footer)   ·   \(pageNumber)", attributes: [
            .font: font(8), .foregroundColor: rgb(0x8A8A8A),
        ])
        footer.draw(at: CGPoint(x: margin.left, y: pageSize.height - margin.bottom + 26))

        NSGraphicsContext.current = nil
        pdf.restoreGState()
        pdf.endPDFPage()
    }
}
pdf.closePDF()

// MARK: - Verificare cu PDFKit (fără ca PDF-ul să fie citit de un om)

guard let document = PDFDocument(url: output), document.pageCount > 0 else {
    fatalError("PDF-ul generat nu se deschide")
}
let fullText = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
let required = guides.flatMap { $0.sections.map(\.heading) }
let missing = required.filter { !fullText.contains($0) }
guard missing.isEmpty else { fatalError("Secțiuni lipsă din PDF: \(missing)") }

// Orientare: primul caracter („G” din titlu) trebuie să fie sus-stânga pe
// pagină (PDF are originea jos) — un text oglindit ar pica aici.
let first = document.page(at: 0)!.characterBounds(at: 0)
guard first.minX < margin.left + 5, first.minY > pageSize.height / 2, first.height > 0 else {
    fatalError("Textul nu e orientat corect: primul caracter la \(first)")
}

// Margini: niciun caracter în afara zonei de text (revărsare la dreapta,
// text sub subsol sau peste marginea de sus).
for index in 0..<document.pageCount {
    guard let page = document.page(at: index), let string = page.string else { continue }
    for (offset, scalar) in string.unicodeScalars.enumerated() where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
        let bounds = page.characterBounds(at: offset)
        guard bounds.width > 0 else { continue }
        guard bounds.maxX <= pageSize.width - margin.right + 2, bounds.minX >= margin.left - 2,
              bounds.minY >= 20, bounds.maxY <= pageSize.height - margin.top + 4 else {
            fatalError("Pagina \(index + 1): caracter în afara marginilor la \(bounds)")
        }
    }
}

print("✓ \(output.lastPathComponent): \(document.pageCount) pagini, \(required.count) secțiuni în 3 limbi, orientare corectă, fără cuvinte interzise.")
