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
            "Dă dublu-click pe <b>GDC Firewall</b>. Dacă aplicația nu e în folderul Aplicații, te întreabă dacă o mută acolo: apasă <b>„Mută în Aplicații”</b>. De acolo se actualizează singură și are permisiunile corecte.",
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
            "Dacă nu vrei să dai parola, exportă regulile din Little Snitch într-un fișier și apasă <b>„Din fișier…”</b>, apoi alege fișierul <b>.lsrules</b> sau <b>.json</b>.",
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
            "<b>„Repornește Mac-ul pentru a finaliza actualizarea”</b> — după o actualizare, macOS a pornit filtrul nou înainte să-l elibereze pe cel vechi. Filtrul merge, dar fără alerte, până la repornire. Repornește Mac-ul o dată.",
            "<b>„Motor oprit”</b> — aplicația nu comunică încă cu filtrul. Dacă nu trece în câteva minute, repornește Mac-ul.",
        ])),
        Section(heading: "5. Modul Silențios (Aprobare inteligentă)", body: .note(
            "Este pornit din prima clipă. Aprobă automat, fără să te întrebe, doar componentele semnate oficial de Apple — altfel ai primi zeci de întrebări în prima oră. Tot ce NU e Apple te întreabă în continuare, de fiecare dată. Ce a aprobat singur vezi în <b>Setări → General → Aprobate automat</b>; tot de acolo îl poți opri.")),
        Section(heading: "6. Panoul de reguli", body: .bullets([
            "Se deschide din meniu: <b>„Reguli…”</b>.",
            "<b>Aplicații Verificate</b> — programele cărora le-ai dat voie pe internet. <b>Servicii Sistem</b> — componentele macOS. <b>Reguli Blocate</b> — tot ce ai oprit.",
            "Fiecare rând are numele aplicației pe înțelesul tuturor, numele tehnic dedesubt și un comutator. Muți comutatorul și regula se schimbă imediat.",
            "Coșul de gunoi din dreapta șterge regula — data viitoare vei fi întrebat din nou despre acel program.",
        ])),
        Section(heading: "7. Filtrare și AdBlock — cele trei nivele", body: .bullets([
            "<b>Minim (Recomandat)</b> — blochează domeniile confirmate de malware, phishing și telemetrie agresivă.",
            "<b>Mediu</b> — adaugă reclamele comune și scripturile de urmărire.",
            "<b>Maxim</b> — adaugă conținutul pentru adulți și site-urile de jocuri de noroc. Potrivit pentru un Mac folosit de copii.",
            "Nivelele se adună: dacă bifezi Maxim, primești și ce blochează Minim și Mediu. Butonul <b>„Actualizare liste”</b> descarcă ultima versiune.",
            "Listele vin din proiectul public StevenBlack/hosts și rulează local — nu se trimite nimic în afară.",
        ])),
        Section(heading: "8. Limba și aspectul", body: .text(
            "Aplicația vorbește română, engleză și spaniolă. Implicit urmează limba Mac-ului; în <b>Setări → General → Limbă</b> poți alege una anume. Tot acolo, <b>Temă</b> alege între Sistem, Light și Dark. Ambele se aplică imediat, fără repornire.")),
        Section(heading: "9. Actualizarea", body: .note(
            "Aplicația verifică actualizările la fiecare pornire. Fereastra are două butoane: <b>„Actualizează acum”</b> descarcă și instalează singur noua versiune — îți cere parola de administrator, apoi aplicația repornește; <b>„Mai târziu”</b> o închide până la versiunea următoare. Nu e o actualizare silențioasă în fundal: tu decizi când se întâmplă.<br/><br/>Există și fereastra <b>„Actualizare critică de securitate”</b>, când motorul de filtrare nu mai e susținut. Aceea nu are „Mai târziu” și reapare la fiecare pornire. Dacă după actualizare meniul arată <b>„Repornește Mac-ul pentru a finaliza actualizarea”</b>, repornește Mac-ul.")),
        Section(heading: "10. Dezinstalare", body: .steps([
            "Din arhiva descărcată, dă dublu-click pe <b>Dezinstalare_GDCFirewall.command</b>.",
            "Dacă scriptul spune că extensia e încă instalată, oprește GDC Firewall în <b>Setări de sistem → General → Elemente de conectare și extensii → Extensii de rețea</b>, apoi rulează scriptul din nou.",
            "Pentru a șterge regulile firewall-ului, scriptul îți cere parola de administrator (nu se vede cât tastezi; apasă Enter). Un LuLu instalat separat rămâne neatins.",
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
            "Double-click <b>GDC Firewall</b>. If the app is not in your Applications folder, it offers to move itself there: click <b>“Move to Applications”</b>. From there it updates itself and has the right permissions.",
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
            "If you prefer not to enter the password, export the rules from Little Snitch to a file, click <b>“From file…”</b> and choose the <b>.lsrules</b> or <b>.json</b> file.",
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
            "<b>“Restart your Mac to finish the update”</b> — after an update, macOS started the new filter before releasing the old one. Filtering works, but without alerts, until you restart. Restart your Mac once.",
            "<b>“Engine stopped”</b> — the app cannot reach the filter yet. If it does not clear within a few minutes, restart your Mac.",
        ])),
        Section(heading: "5. Silent Mode (smart approval)", body: .note(
            "It is on from the very first launch. It silently allows only components officially signed by Apple — otherwise you would face dozens of prompts in the first hour. Anything not from Apple still asks you, every time. Whatever it approved on its own is listed under <b>Settings → General → Approved automatically</b>, where you can also turn it off.")),
        Section(heading: "6. The rules panel", body: .bullets([
            "Open it from the menu: <b>“Rules…”</b>.",
            "<b>Verified Apps</b> — programs you allowed onto the internet. <b>System Services</b> — macOS components. <b>Blocked Rules</b> — everything you stopped.",
            "Each row shows the app's plain-language name, the technical name below and a switch. Flip the switch and the rule changes immediately.",
            "The trash icon on the right deletes the rule — next time you will be asked about that program again.",
        ])),
        Section(heading: "7. Filtering and ad blocking — three levels", body: .bullets([
            "<b>Minimum (Recommended)</b> — blocks confirmed malware, phishing and aggressive telemetry domains.",
            "<b>Medium</b> — adds common ads and tracking scripts.",
            "<b>Maximum</b> — adds adult content and gambling sites. Suitable for a Mac used by children.",
            "Levels add up: ticking Maximum also gives you Minimum and Medium. The <b>“Update lists”</b> button downloads the latest version.",
            "Lists come from the public StevenBlack/hosts project and run locally — nothing is sent out.",
        ])),
        Section(heading: "8. Language and appearance", body: .text(
            "The app speaks Romanian, English and Spanish. By default it follows your Mac's language; in <b>Settings → General → Language</b> you can pick one. In the same place, <b>Theme</b> chooses between System, Light and Dark. Both apply immediately, without a restart.")),
        Section(heading: "9. Updates", body: .note(
            "The app checks for updates at every launch. The window has two buttons: <b>“Update now”</b> downloads and installs the new version for you — it asks for your administrator password, then the app restarts; <b>“Later”</b> dismisses it until the next version. This is not a silent background update: you decide when it happens.<br/><br/>There is also a <b>“Critical security update”</b> window, shown when the filtering engine is no longer supported. That one has no “Later” and returns at every launch. If after an update the menu reads <b>“Restart your Mac to finish the update”</b>, restart your Mac.")),
        Section(heading: "10. Uninstalling", body: .steps([
            "From the downloaded archive, double-click <b>Dezinstalare_GDCFirewall.command</b>.",
            "If the script says the extension is still installed, turn GDC Firewall off in <b>System Settings → General → Login Items &amp; Extensions → Network Extensions</b>, then run the script again.",
            "To delete the firewall's rules, the script asks for your administrator password (invisible while you type; press Enter). A separately installed LuLu is left untouched.",
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
            "Haz doble clic en <b>GDC Firewall</b>. Si la app no está en la carpeta Aplicaciones, te ofrece moverse allí: pulsa <b>«Mover a Aplicaciones»</b>. Desde allí se actualiza sola y tiene los permisos correctos.",
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
            "Si prefieres no dar la contraseña, exporta las reglas de Little Snitch a un archivo, pulsa <b>«Desde archivo…»</b> y elige el archivo <b>.lsrules</b> o <b>.json</b>.",
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
            "<b>«Reinicia el Mac para terminar la actualización»</b> — tras una actualización, macOS inició el filtro nuevo antes de liberar el antiguo. El filtrado funciona, pero sin alertas, hasta reiniciar. Reinicia el Mac una vez.",
            "<b>«Motor detenido»</b> — la app aún no se comunica con el filtro. Si no se resuelve en unos minutos, reinicia el Mac.",
        ])),
        Section(heading: "5. Modo silencioso (aprobación inteligente)", body: .note(
            "Está activado desde el primer momento. Aprueba en silencio solo los componentes firmados oficialmente por Apple; de lo contrario recibirías decenas de avisos en la primera hora. Todo lo que no sea de Apple te sigue preguntando, siempre. Lo que aprobó por su cuenta aparece en <b>Ajustes → General → Aprobados automáticamente</b>, donde también puedes desactivarlo.")),
        Section(heading: "6. El panel de reglas", body: .bullets([
            "Se abre desde el menú: <b>«Reglas…»</b>.",
            "<b>Apps verificadas</b> — programas a los que diste acceso a internet. <b>Servicios del sistema</b> — componentes de macOS. <b>Reglas bloqueadas</b> — todo lo que has detenido.",
            "Cada fila muestra el nombre sencillo de la app, el nombre técnico debajo y un interruptor. Al moverlo, la regla cambia al instante.",
            "El icono de papelera a la derecha elimina la regla: la próxima vez se te volverá a preguntar por ese programa.",
        ])),
        Section(heading: "7. Filtrado y AdBlock — tres niveles", body: .bullets([
            "<b>Mínimo (Recomendado)</b> — bloquea dominios confirmados de malware, phishing y telemetría agresiva.",
            "<b>Medio</b> — añade los anuncios comunes y los scripts de rastreo.",
            "<b>Máximo</b> — añade contenido para adultos y sitios de apuestas. Indicado para un Mac que usan niños.",
            "Los niveles se suman: si marcas Máximo, también obtienes Mínimo y Medio. El botón <b>«Actualizar listas»</b> descarga la última versión.",
            "Las listas provienen del proyecto público StevenBlack/hosts y funcionan localmente: no se envía nada fuera.",
        ])),
        Section(heading: "8. Idioma y apariencia", body: .text(
            "La app habla rumano, inglés y español. Por defecto sigue el idioma del Mac; en <b>Ajustes → General → Idioma</b> puedes elegir uno. En el mismo lugar, <b>Tema</b> elige entre Sistema, Claro y Oscuro. Ambos se aplican al instante, sin reiniciar.")),
        Section(heading: "9. Actualizaciones", body: .note(
            "La app busca actualizaciones en cada inicio. La ventana tiene dos botones: <b>«Actualizar ahora»</b> descarga e instala sola la nueva versión — te pide la contraseña de administrador y luego la app se reinicia; <b>«Más tarde»</b> la cierra hasta la siguiente versión. No es una actualización silenciosa en segundo plano: tú decides cuándo ocurre.<br/><br/>También existe la ventana <b>«Actualización de seguridad crítica»</b>, cuando el motor de filtrado ya no está soportado. Esa no tiene «Más tarde» y vuelve en cada inicio. Si tras actualizar el menú indica <b>«Reinicia el Mac para terminar la actualización»</b>, reinicia el Mac.")),
        Section(heading: "10. Desinstalación", body: .steps([
            "Desde el archivo descargado, haz doble clic en <b>Dezinstalare_GDCFirewall.command</b>.",
            "Si el script indica que la extensión sigue instalada, desactiva GDC Firewall en <b>Ajustes del Sistema → General → Ítems de inicio y extensiones → Extensiones de red</b> y vuelve a ejecutar el script.",
            "Para borrar las reglas del firewall, el script te pide la contraseña de administrador (no se ve mientras la escribes; pulsa Intro). Un LuLu instalado aparte no se toca.",
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
