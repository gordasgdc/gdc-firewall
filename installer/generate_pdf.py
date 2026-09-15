# Genereaza Instructiuni_Utilizare.pdf (RO/EN/ES) cu reportlab.
# Foloseste Arial, nu Helvetica standard-14: fontul de baza al PDF-ului nu
# are diacriticele romanesti si le-ar desena ca patratele goale.
# Ruleaza cu: python3 installer/generate_pdf.py
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, ListFlowable,
                                ListItem, PageBreak, Spacer)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Instructiuni_Utilizare.pdf")

pdfmetrics.registerFont(TTFont("Arial", "/System/Library/Fonts/Supplemental/Arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"))

styles = getSampleStyleSheet()
ACCENT = colors.HexColor("#C97D2E")
MUTED = colors.HexColor("#6a6a6a")
INK = colors.HexColor("#1a1a1a")
NOTE_BG = colors.HexColor("#FBF1E6")
ALERT_BG = colors.HexColor("#FDECEC")
ALERT_INK = colors.HexColor("#8F2323")

title_style = ParagraphStyle("Title", parent=styles["Title"], fontName="Arial-Bold",
                             fontSize=19, spaceAfter=2, textColor=INK)
subtitle_style = ParagraphStyle("Subtitle", parent=styles["Normal"], fontName="Arial",
                                fontSize=11, textColor=MUTED, spaceAfter=18)
h2_style = ParagraphStyle("H2", parent=styles["Heading2"], fontName="Arial-Bold",
                          fontSize=13, textColor=ACCENT, spaceBefore=15, spaceAfter=6)
h2_alert = ParagraphStyle("H2Alert", parent=h2_style, textColor=ALERT_INK)
body_style = ParagraphStyle("Body", parent=styles["Normal"], fontName="Arial",
                            fontSize=10.5, leading=15, textColor=INK, spaceAfter=6)
step_style = ParagraphStyle("Step", parent=body_style, leftIndent=4, spaceAfter=5)
note_style = ParagraphStyle("Note", parent=body_style, backColor=NOTE_BG,
                            leftIndent=10, rightIndent=10, fontSize=10,
                            borderPadding=7, spaceBefore=4, spaceAfter=8)
alert_style = ParagraphStyle("Alert", parent=note_style, backColor=ALERT_BG,
                             textColor=ALERT_INK, fontName="Arial-Bold")
footer_style = ParagraphStyle("Footer", parent=styles["Normal"], fontName="Arial",
                              fontSize=8.5, textColor=colors.HexColor("#8a8a8a"),
                              spaceBefore=18)


def numbered(items):
    return ListFlowable(
        [ListItem(Paragraph(it, step_style), leftIndent=16) for it in items],
        bulletType="1", start="1", leftIndent=16, spaceBefore=2, spaceAfter=8,
    )


def bullets(items):
    return ListFlowable(
        [ListItem(Paragraph(it, step_style), leftIndent=16) for it in items],
        bulletType="bullet", leftIndent=16, spaceBefore=2, spaceAfter=8,
    )


def page(d):
    """O sectiune poate fi: text simplu, lista numerotata (list), lista cu
    buline (set-ul e nepotrivit, deci folosim tuple ('bullets', [...])),
    o caseta de nota (('note', text)) sau una de avertisment (('alert', text))."""
    flow = [Paragraph("GDC Firewall", title_style),
            Paragraph(d["subtitle"], subtitle_style)]
    for heading, body in d["sections"]:
        flow.append(Paragraph(heading, h2_alert if heading.startswith("0.") else h2_style))
        if isinstance(body, list):
            flow.append(numbered(body))
        elif isinstance(body, tuple):
            kind, payload = body
            if kind == "bullets":
                flow.append(bullets(payload))
            elif kind == "alert":
                flow.append(Paragraph(payload, alert_style))
            else:
                flow.append(Paragraph(payload, note_style))
        else:
            flow.append(Paragraph(body, body_style))
    flow.append(Spacer(1, 6))
    flow.append(Paragraph(d["footer"], footer_style))
    return flow


# ---------------------------------------------------------------------------
# Romana
# ---------------------------------------------------------------------------
RO = dict(
    subtitle="Ghid de instalare și utilizare — Română",
    sections=[
        ("0. PASUL CRITIC — Aprobarea extensiei de rețea", (
            "alert",
            "Până când nu faci acest pas, GDC Firewall NU blochează nimic. "
            "Aplicația pornește, meniul funcționează, dar filtrul este oprit. "
            "Este singurul pas pe care macOS nu îl poate face în locul tău.")),
        ("Cum aprobi extensia, pas cu pas", [
            "Pornește GDC Firewall. La prima lansare apare o fereastră de la macOS: "
            "<b>„Extensie de sistem blocată”</b>. Apasă <b>„Deschide Setări de sistem”</b>. "
            "Dacă ai închis fereastra din greșeală, deschide manual "
            "<b>Setări de sistem → General → Elemente de conectare și extensii</b>.",
            "Caută secțiunea <b>Extensii de rețea</b> și apasă butonul <b>(i)</b> din dreapta ei.",
            "Bifează comutatorul din dreptul <b>GDC Firewall</b>, apoi apasă <b>Gata</b>.",
            "macOS îți cere parola de administrator a Mac-ului (parola cu care te loghezi). "
            "Scrie-o și apasă Enter. Parola nu se vede pe ecran în timp ce o tastezi — e normal.",
            "Deschide <b>Setări de sistem → Rețea → Filtre</b> și verifică "
            "<b>GDC Firewall</b> apare acolo, activ.",
            "Revino în GDC Firewall: pictograma din bara de sus trebuie să arate acum "
            "<b>„Protecție activă”</b>. Dacă scrie „Motor oprit”, repetă pașii 2–3.",
        ]),
        ("De ce cere macOS asta", (
            "note",
            "Un firewall trebuie să vadă fiecare conexiune de rețea a fiecărei aplicații. "
            "Apple nu permite niciunui program să facă asta fără acordul tău explicit, dat "
            "o singură dată, din Setări de sistem. Este o protecție pentru tine, nu o "
            "problemă a aplicației.")),
        ("1. Instalare", [
            "Descarcă pachetul de pe <b>gordas.dev/gdc-firewall</b>.",
            "Dă dublu-click pe fișierul <b>.pkg</b> și urmează pașii. "
            "Aplicația se instalează direct în folderul Aplicații.",
            "Pornește <b>GDC Firewall</b> din Aplicații, apoi fă pasul 0 de mai sus.",
        ]),
        ("2. Sistemul Semafor — ce înseamnă culorile", (
            "bullets",
            ["<b>Verde — Sigur.</b> Programul face parte din macOS și e semnat oficial de "
             "Apple. Recomandarea afișată este <b>„Aprobă (Recomandat)”</b>. Blocarea lui "
             "poate strica funcții ale sistemului (iCloud, imprimante, notificări).",
             "<b>Galben — Aplicație cunoscută.</b> Programul e semnat de un dezvoltator "
             "identificat, dar nu face parte din macOS. Recomandarea este "
             "<b>„Verifică aplicația”</b> — aprob-o doar dacă o recunoști.",
             "<b>Roșu — Neidentificat.</b> Nu se știe cine a scris programul. Recomandarea "
             "este <b>„Blochează accesul”</b>. Dacă nu l-ai instalat tu conștient, blochează-l."])),
        ("Cum răspunzi la o alertă", [
            "Citește numele scris mare — e numele în română al programului, nu numele tehnic.",
            "Uită-te la insigna colorată și la recomandarea de sub butoane.",
            "Lasă bifat <b>„Ține minte alegerea”</b> dacă vrei ca răspunsul să devină o regulă "
            "permanentă. Debifează-l dacă vrei să decizi doar de data asta.",
            "Apasă <b>Permite</b> sau <b>Blochează</b>. Fereastra nu se poate închide altfel — "
            "conexiunea chiar așteaptă răspunsul tău.",
        ]),
        ("3. Modul Auto-Pilot (Aprobare inteligentă)", (
            "note",
            "Este pornit din prima clipă. Aprobă automat, fără să te întrebe, doar "
            "componentele semnate oficial de Apple — altfel ai primi zeci de întrebări în "
            "prima oră și ai dezinstala aplicația. Tot ce NU e Apple te întreabă în "
            "continuare, de fiecare dată. Ce a aprobat singur poți vedea oricând în "
            "<b>Setări → General → Aprobate automat</b>. Îl poți opri din același loc.")),
        ("4. Panoul de reguli", (
            "bullets",
            ["<b>Aplicații Verificate</b> — programele cărora le-ai dat voie pe internet.",
             "<b>Servicii Sistem</b> — componentele macOS, aprobate de tine sau de Auto-Pilot.",
             "<b>Reguli Blocate</b> — tot ce ai oprit.",
             "Fiecare rând are pictograma aplicației, numele ei în română, numele tehnic "
             "dedesubt și un comutator. Muți comutatorul și regula se schimbă imediat.",
             "Coșul de gunoi din dreapta rândului șterge regula — data viitoare vei fi "
             "întrebat din nou despre acel program."])),
        ("5. Filtrare și AdBlock — cele trei nivele", (
            "bullets",
            ["<b>Minim (Recomandat)</b> — blochează domeniile confirmate de malware, "
             "phishing și telemetrie agresivă. Nu strică nimic din ce folosești zilnic.",
             "<b>Mediu</b> — adaugă reclamele comune și scripturile de urmărire.",
             "<b>Maxim</b> — adaugă conținutul pentru adulți și site-urile de pariuri. "
             "Potrivit pentru un Mac folosit de copii.",
             "Nivelele se adună: dacă bifezi Maxim, primești și ce blochează Minim și Mediu.",
             "Butonul <b>Actualizare liste</b> descarcă ultima versiune a listelor. "
             "Se face și automat, la pornirea aplicației.",
             "Listele provin din proiectul public StevenBlack. Filtrarea rulează local, "
             "în memoria Mac-ului tău — nu se trimite nimic în afară și nu încetinește "
             "navigarea."])),
        ("6. Actualizarea", (
            "note",
            "Aplicația verifică actualizările la fiecare pornire. Pop-up-ul are două "
            "butoane: <b>„Actualizează acum”</b> descarcă și instalează singur noua "
            "versiune (îți va cere parola de administrator), iar <b>„Mai târziu”</b> închide "
            "fereastra până la versiunea următoare. Nu este o actualizare silențioasă în "
            "fundal — tu decizi când se întâmplă.<br/><br/>"
            "Există un al doilea tip de pop-up, marcat <b>„Actualizare critică de "
            "securitate”</b>: apare când motorul de filtrare din aplicație nu mai este "
            "susținut. Acela nu are buton „Mai târziu” și reapare la fiecare pornire, "
            "fiindcă până la actualizare protecția ta chiar este mai slabă.")),
        ("7. Dezinstalare", [
            "Deschide arhiva descărcată și dă dublu-click pe "
            "<b>Dezinstalare_GDCFirewall.command</b>.",
            "Dacă scriptul îți spune că extensia e încă instalată, du-te în "
            "<b>Setări de sistem → General → Elemente de conectare și extensii → "
            "Extensii de rețea</b>, debifează GDC Firewall, apoi rulează scriptul din nou.",
            "Scriptul șterge aplicația și toate fișierele ei: preferințe, liste descărcate, "
            "jurnale. Nu lasă nimic în urmă.",
        ]),
        ("8. Susținere și licență", (
            "note",
            "GDC Firewall este gratuit și rămâne gratuit. Dacă îți este de folos, o donație "
            "de <b>23 €</b> acoperă timpul de întreținere și taxele de dezvoltator Apple. "
            "Nu este un preț și nu deblochează nimic — toate funcțiile sunt deja "
            "disponibile.<br/><br/>"
            "Aplicația este distribuită sub licența GPL-3.0, cu sursa publică. Motorul de "
            "filtrare este LuLu, © Objective-See.")),
    ],
    footer="GDC Firewall — gordas.dev/gdc-firewall · © 2026 Cristi Gordaș / GDC · "
           "GPL-3.0 · Motor: LuLu © Objective-See",
)

# ---------------------------------------------------------------------------
# English
# ---------------------------------------------------------------------------
EN = dict(
    subtitle="Installation and user guide — English",
    sections=[
        ("0. CRITICAL STEP — Approving the network extension", (
            "alert",
            "Until you complete this step, GDC Firewall blocks NOTHING. The app starts, "
            "the menu works, but the filter is off. This is the one step macOS cannot "
            "do for you.")),
        ("Approving the extension, step by step", [
            "Launch GDC Firewall. On first run macOS shows a window: "
            "<b>“System Extension Blocked”</b>. Click <b>“Open System Settings”</b>. "
            "If you closed it by accident, open "
            "<b>System Settings → General → Login Items &amp; Extensions</b> yourself.",
            "Find the <b>Network Extensions</b> section and click the <b>(i)</b> button next to it.",
            "Turn on the switch for <b>GDC Firewall</b>, then click <b>Done</b>.",
            "macOS asks for your Mac administrator password (the one you log in with). "
            "Type it and press Enter. The password stays invisible while you type — that is normal.",
            "Open <b>System Settings → Network → Filters</b> and confirm "
            "<b>GDC Firewall</b> is listed and active.",
            "Go back to GDC Firewall: the menu bar icon should now read "
            "<b>“Protecție activă”</b> (protection active). If it says “Motor oprit”, repeat steps 2–3.",
        ]),
        ("Why macOS asks for this", (
            "note",
            "A firewall has to see every network connection of every application. Apple "
            "does not let any program do that without your explicit consent, given once, "
            "in System Settings. It protects you; it is not a fault of the app.")),
        ("1. Installation", [
            "Download the package from <b>gordas.dev/gdc-firewall</b>.",
            "Double-click the <b>.pkg</b> file and follow the steps. The app installs "
            "straight into your Applications folder.",
            "Launch <b>GDC Firewall</b> from Applications, then complete step 0 above.",
        ]),
        ("2. The traffic-light system", (
            "bullets",
            ["<b>Green — Safe.</b> The program is part of macOS and officially signed by "
             "Apple. The shown recommendation is <b>“Approve (Recommended)”</b>. Blocking it "
             "may break system features (iCloud, printers, notifications).",
             "<b>Yellow — Known application.</b> Signed by an identified developer, but not "
             "part of macOS. The recommendation is <b>“Check the application”</b> — approve "
             "it only if you recognise it.",
             "<b>Red — Unidentified.</b> Nobody knows who wrote this program. The "
             "recommendation is <b>“Block access”</b>. If you did not install it knowingly, "
             "block it."])),
        ("Answering an alert", [
            "Read the large name — it is the plain-language name, not the technical one.",
            "Look at the coloured badge and at the recommendation under the buttons.",
            "Leave <b>“Remember this choice”</b> ticked to turn your answer into a permanent "
            "rule. Untick it to decide just this once.",
            "Press <b>Permite</b> (Allow) or <b>Blochează</b> (Block). The window cannot be "
            "closed any other way — a real connection is waiting for your answer.",
        ]),
        ("3. Auto-Pilot mode (smart approval)", (
            "note",
            "It is on from the very first launch. It silently approves only components "
            "officially signed by Apple — otherwise you would face dozens of prompts in the "
            "first hour and uninstall the app. Anything not from Apple still asks you, every "
            "time. Whatever it approved on its own is listed under "
            "<b>Settings → General</b>, where you can also switch it off.")),
        ("4. The rules panel", (
            "bullets",
            ["<b>Verified Applications</b> — programs you allowed onto the internet.",
             "<b>System Services</b> — macOS components, approved by you or by Auto-Pilot.",
             "<b>Blocked Rules</b> — everything you stopped.",
             "Each row shows the app icon, its plain-language name, the technical name "
             "below, and a switch. Flip the switch and the rule changes immediately.",
             "The trash icon on the right deletes the rule — next time you will be asked "
             "about that program again."])),
        ("5. Filtering and ad blocking — three levels", (
            "bullets",
            ["<b>Minimum (Recommended)</b> — blocks confirmed malware, phishing and "
             "aggressive telemetry domains. It breaks nothing you use daily.",
             "<b>Medium</b> — adds common advertising and tracking scripts.",
             "<b>Maximum</b> — adds adult content and gambling sites. Suitable for a Mac "
             "used by children.",
             "Levels stack: ticking Maximum also gives you Minimum and Medium.",
             "The <b>Update lists</b> button downloads the latest version. It also happens "
             "automatically when the app starts.",
             "Lists come from the public StevenBlack project. Filtering runs locally, in "
             "your Mac's memory — nothing is sent out and browsing is not slowed down."])),
        ("6. Updates", (
            "note",
            "The app checks for updates at every launch. The pop-up has two buttons: "
            "<b>“Actualizează acum”</b> (Update now) downloads and installs the new version "
            "for you (it will ask for your administrator password), and "
            "<b>“Mai târziu”</b> (Later) dismisses it until the next version. This is not a "
            "silent background update — you decide when it happens.<br/><br/>"
            "There is a second kind of pop-up, marked as a <b>critical security update</b>: "
            "it appears when the filtering engine inside the app is no longer supported. "
            "That one has no “Later” button and returns at every launch, because until you "
            "update, your protection really is weaker.")),
        ("7. Uninstalling", [
            "Open the downloaded archive and double-click "
            "<b>Dezinstalare_GDCFirewall.command</b>.",
            "If the script tells you the extension is still installed, go to "
            "<b>System Settings → General → Login Items &amp; Extensions → Network "
            "Extensions</b>, switch GDC Firewall off, then run the script again.",
            "The script removes the app and all of its files: preferences, downloaded "
            "lists, logs. Nothing is left behind.",
        ]),
        ("8. Support and licence", (
            "note",
            "GDC Firewall is free and stays free. If you find it useful, a <b>€23</b> "
            "donation covers maintenance time and Apple developer fees. It is not a price "
            "and it unlocks nothing — every feature is already available.<br/><br/>"
            "The app is distributed under the GPL-3.0 licence, with public source code. "
            "The filtering engine is LuLu, © Objective-See.")),
    ],
    footer="GDC Firewall — gordas.dev/gdc-firewall · © 2026 Cristi Gordaș / GDC · "
           "GPL-3.0 · Engine: LuLu © Objective-See",
)

# ---------------------------------------------------------------------------
# Espanol
# ---------------------------------------------------------------------------
ES = dict(
    subtitle="Guía de instalación y uso — Español",
    sections=[
        ("0. PASO CRÍTICO — Aprobar la extensión de red", (
            "alert",
            "Hasta que completes este paso, GDC Firewall NO bloquea NADA. La aplicación "
            "se inicia, el menú funciona, pero el filtro está apagado. Es el único paso "
            "que macOS no puede hacer por ti.")),
        ("Cómo aprobar la extensión, paso a paso", [
            "Abre GDC Firewall. La primera vez, macOS muestra una ventana: "
            "<b>«Extensión del sistema bloqueada»</b>. Pulsa <b>«Abrir Ajustes del Sistema»</b>. "
            "Si la cerraste sin querer, abre tú mismo "
            "<b>Ajustes del Sistema → General → Ítems de inicio y extensiones</b>.",
            "Busca la sección <b>Extensiones de red</b> y pulsa el botón <b>(i)</b> que está a su lado.",
            "Activa el interruptor de <b>GDC Firewall</b> y pulsa <b>Listo</b>.",
            "macOS te pide la contraseña de administrador del Mac (la que usas para "
            "iniciar sesión). Escríbela y pulsa Intro. La contraseña no se ve mientras "
            "la escribes — es normal.",
            "Abre <b>Ajustes del Sistema → Red → Filtros</b> y comprueba que "
            "<b>GDC Firewall</b> aparece ahí, activo.",
            "Vuelve a GDC Firewall: el icono de la barra superior debe indicar "
            "<b>«Protecție activă»</b> (protección activa). Si pone «Motor oprit», repite "
            "los pasos 2 y 3.",
        ]),
        ("Por qué macOS pide esto", (
            "note",
            "Un cortafuegos necesita ver cada conexión de red de cada aplicación. Apple no "
            "permite que ningún programa haga eso sin tu consentimiento explícito, dado una "
            "sola vez, en Ajustes del Sistema. Es una protección para ti, no un fallo de la "
            "aplicación.")),
        ("1. Instalación", [
            "Descarga el paquete desde <b>gordas.dev/gdc-firewall</b>.",
            "Haz doble clic en el archivo <b>.pkg</b> y sigue los pasos. La aplicación se "
            "instala directamente en la carpeta Aplicaciones.",
            "Abre <b>GDC Firewall</b> desde Aplicaciones y completa el paso 0 anterior.",
        ]),
        ("2. El sistema de semáforo", (
            "bullets",
            ["<b>Verde — Seguro.</b> El programa forma parte de macOS y está firmado "
             "oficialmente por Apple. La recomendación mostrada es <b>«Aprobar "
             "(Recomendado)»</b>. Bloquearlo puede estropear funciones del sistema (iCloud, "
             "impresoras, notificaciones).",
             "<b>Amarillo — Aplicación conocida.</b> Firmada por un desarrollador "
             "identificado, pero no forma parte de macOS. La recomendación es "
             "<b>«Verifica la aplicación»</b>: apruébala solo si la reconoces.",
             "<b>Rojo — No identificado.</b> No se sabe quién escribió este programa. La "
             "recomendación es <b>«Bloquear el acceso»</b>. Si no lo instalaste "
             "conscientemente, bloquéalo."])),
        ("Cómo responder a una alerta", [
            "Lee el nombre grande: es el nombre en lenguaje sencillo, no el técnico.",
            "Fíjate en la insignia de color y en la recomendación bajo los botones.",
            "Deja marcado <b>«Recordar esta elección»</b> si quieres que tu respuesta se "
            "convierta en una regla permanente. Desmárcalo para decidir solo esta vez.",
            "Pulsa <b>Permite</b> (Permitir) o <b>Blochează</b> (Bloquear). La ventana no se "
            "puede cerrar de otra forma: una conexión real está esperando tu respuesta.",
        ]),
        ("3. Modo Auto-Pilot (aprobación inteligente)", (
            "note",
            "Está activado desde el primer momento. Aprueba en silencio únicamente los "
            "componentes firmados oficialmente por Apple; de lo contrario recibirías "
            "decenas de avisos en la primera hora y desinstalarías la aplicación. Todo lo "
            "que no sea de Apple te sigue preguntando, siempre. Lo que aprobó por su cuenta "
            "aparece en <b>Ajustes → General</b>, donde también puedes desactivarlo.")),
        ("4. El panel de reglas", (
            "bullets",
            ["<b>Aplicaciones verificadas</b> — programas a los que diste acceso a internet.",
             "<b>Servicios del sistema</b> — componentes de macOS, aprobados por ti o por "
             "Auto-Pilot.",
             "<b>Reglas bloqueadas</b> — todo lo que has detenido.",
             "Cada fila muestra el icono de la aplicación, su nombre sencillo, el nombre "
             "técnico debajo y un interruptor. Al moverlo, la regla cambia al instante.",
             "El icono de papelera a la derecha borra la regla: la próxima vez se te "
             "volverá a preguntar por ese programa."])),
        ("5. Filtrado y bloqueo de anuncios — tres niveles", (
            "bullets",
            ["<b>Mínimo (Recomendado)</b> — bloquea dominios confirmados de malware, "
             "phishing y telemetría agresiva. No rompe nada de lo que usas a diario.",
             "<b>Medio</b> — añade los anuncios habituales y los scripts de rastreo.",
             "<b>Máximo</b> — añade contenido para adultos y sitios de apuestas. Indicado "
             "para un Mac que usan niños.",
             "Los niveles se suman: si marcas Máximo, también obtienes Mínimo y Medio.",
             "El botón <b>Actualizar listas</b> descarga la última versión. También ocurre "
             "automáticamente al iniciar la aplicación.",
             "Las listas provienen del proyecto público StevenBlack. El filtrado se ejecuta "
             "localmente, en la memoria de tu Mac: no se envía nada fuera y la navegación no "
             "se ralentiza."])),
        ("6. Actualizaciones", (
            "note",
            "La aplicación busca actualizaciones en cada inicio. La ventana tiene dos "
            "botones: <b>«Actualizează acum»</b> (Actualizar ahora) descarga e instala sola "
            "la nueva versión (te pedirá la contraseña de administrador), y "
            "<b>«Mai târziu»</b> (Más tarde) la cierra hasta la siguiente versión. No es una "
            "actualización silenciosa en segundo plano: tú decides cuándo ocurre.<br/><br/>"
            "Hay un segundo tipo de ventana, marcada como <b>actualización crítica de "
            "seguridad</b>: aparece cuando el motor de filtrado de la aplicación ya no está "
            "soportado. Esa no tiene botón «Más tarde» y vuelve en cada inicio, porque hasta "
            "que actualices tu protección es realmente más débil.")),
        ("7. Desinstalación", [
            "Abre el archivo descargado y haz doble clic en "
            "<b>Dezinstalare_GDCFirewall.command</b>.",
            "Si el script te dice que la extensión sigue instalada, ve a "
            "<b>Ajustes del Sistema → General → Ítems de inicio y extensiones → Extensiones "
            "de red</b>, desactiva GDC Firewall y vuelve a ejecutar el script.",
            "El script elimina la aplicación y todos sus archivos: preferencias, listas "
            "descargadas, registros. No deja nada atrás.",
        ]),
        ("8. Apoyo y licencia", (
            "note",
            "GDC Firewall es gratuito y seguirá siéndolo. Si te resulta útil, una donación "
            "de <b>23 €</b> cubre el tiempo de mantenimiento y las cuotas de desarrollador "
            "de Apple. No es un precio y no desbloquea nada: todas las funciones ya están "
            "disponibles.<br/><br/>"
            "La aplicación se distribuye bajo la licencia GPL-3.0, con código fuente "
            "público. El motor de filtrado es LuLu, © Objective-See.")),
    ],
    footer="GDC Firewall — gordas.dev/gdc-firewall · © 2026 Cristi Gordaș / GDC · "
           "GPL-3.0 · Motor: LuLu © Objective-See",
)


def build():
    doc = SimpleDocTemplate(OUT, pagesize=A4,
                            leftMargin=48, rightMargin=48,
                            topMargin=46, bottomMargin=42,
                            title="GDC Firewall — Instrucțiuni de utilizare",
                            author="Cristi Gordaș / GDC")
    flow = []
    for i, lang in enumerate((RO, EN, ES)):
        if i:
            flow.append(PageBreak())
        flow.extend(page(lang))
    doc.build(flow)
    print(f"✓ {OUT}")


if __name__ == "__main__":
    build()
