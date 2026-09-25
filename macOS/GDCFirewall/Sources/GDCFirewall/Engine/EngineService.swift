import Foundation

/// Serviciul launchd al extensiei de rețea, văzut din afară.
///
/// Cursa de la actualizare (confirmată în logul launchd): la înlocuire,
/// nesessionmanager trimite jobul extensiei noi cât timp cel vechi încă e în
/// launchd, iar launchd scoate endpoint-ul Mach din DEFINIȚIA jobului nou
/// („The endpoint … already exists and is owned by …”). Ascultătorul XPC al
/// extensiei primește „Operation not permitted” și nu reîncearcă
/// (Extension/XPCListener.m, intangibil).
///
/// Verificat pe rând, 2026-09-18:
///   - `kickstart -k` pe jobul nou NU repară: păstrează definiția (15 încercări);
///   - `bootout` pe jobul nou îl scoate cu tot cu înregistrarea providerului
///     („Found 0 registrations”), iar comutarea filtrului nu-l retrimite —
///     doar o activare/înlocuire sau repornirea Mac-ului înregistrează din nou;
///   - FĂRĂ job vechi în launchd, înlocuirea se înregistrează curat.
/// **Cu SIP activ (Mac-urile clienților) `launchctl bootout` pe acest job e
/// interzis chiar și ca root** („Boot-out failed: 1: Operation not permitted”,
/// verificat 2026-09-25) — înlocuirea secvențială din 2.3.2–2.3.4 mergea doar
/// cu SIP dezactivat. Singura cale este API-ul oficial (activare + `.replace`,
/// ca LuLu upstream); dacă cursa apare, repornirea Mac-ului o rezolvă, iar
/// garda de actualizare ține necunoscutele blocate până atunci.
///
/// Totul aici doar citește (`launchctl print`), fără root.
enum EngineService {
    static let labelPrefix = "NetworkExtension.dev.gordas.GDCFirewall.extension."
    private static let log = DiagnosticLog("engine")

    /// Eticheta serviciului pentru extensia DIN pachetul acestei aplicații:
    /// prefix + CFBundleShortVersionString + "." + CFBundleVersion.
    static var bundledLabel: String? {
        let plist = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/dev.gordas.GDCFirewall.extension.systemextension/Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let short = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return nil }
        return labelPrefix + short + "." + build
    }

    /// Etichetele serviciilor extensiei înregistrate acum în domeniul system
    /// (una normal; două în timpul unei înlocuiri).
    static func runningLabels() -> [String] {
        guard let output = run("/bin/launchctl", ["print", "system"]) else { return [] }
        var labels = Set<String>()
        for line in output.split(separator: "\n") where line.contains(labelPrefix) {
            if let range = line.range(of: labelPrefix) {
                let tail = line[range.upperBound...].prefix { $0.isNumber || $0 == "." }
                labels.insert(labelPrefix + tail)
            }
        }
        return labels.sorted()
    }

    /// `true` = serviciul deține serviciul Mach al daemon-ului (ascultătorul
    /// XPC e viu); `false` = cursa s-a produs; `nil` = serviciul nu există.
    static func ownsMachService(_ label: String) -> Bool? {
        guard let output = run("/bin/launchctl", ["print", "system/\(label)"]),
              output.contains("state =") else { return nil }
        let lines = output.split(separator: "\n").map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("\"\(LuLu.daemonMachService)\" = {") }) else { return false }
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "}" { break }
            if trimmed.hasPrefix("active =") { return trimmed == "active = 1" }
        }
        return false
    }

    /// `true` = în launchd rulează (și) o altă versiune a extensiei decât cea
    /// din pachetul acestei aplicații: aplicația poate fi conectată la motorul
    /// VECHI, deci o actualizare e în curs, chiar dacă activarea n-a pornit încă.
    /// Etichete necitibile (listă goală) sau harnașamentul SPM = nu știm → `false`,
    /// ca garda să nu rămână blocată pe o citire eșuată.
    static func isForeignEngine(running: [String], bundled: String?) -> Bool {
        guard let bundled, !running.isEmpty else { return false }
        return running.contains { $0 != bundled }
    }

    static func foreignEngineRunning() async -> Bool {
        await Task.detached {
            let bundled = bundledLabel
            let running = runningLabels()
            let foreign = isForeignEngine(running: running, bundled: bundled)
            if foreign {
                log.info("Rulează altă versiune a extensiei (\(running.joined(separator: ", "))) decât cea din pachet (\(bundled ?? "?"))")
            }
            return foreign
        }.value
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
}

/// Ce vede garda din motor: `DaemonBridge` în aplicație, un dublu în teste.
@MainActor
protocol UpdateGuardEngine: AnyObject {
    var isConnected: Bool { get }
    func preferences() async -> [String: Any]?
    /// Preferințele motorului DUPĂ aplicare (răspunsul lui); `nil` = netrimise sau fără răspuns.
    func applyPreferences(_ preferences: [String: Any]) async -> [String: Any]?
}

/// Garda de actualizare: cât timp aplicația nu vorbește cu extensia nouă,
/// motorul ar PERMITE automat orice conexiune necunoscută (Extension/
/// FilterDataProvider.m, `allowNoClient`). Modul pasiv e verificat ÎNAINTEA
/// acelei ramuri, deci îl pornim pe „blochează, fără reguli automate” pe
/// extensia veche, înainte de înlocuire: preferințele se salvează pe disc,
/// iar extensia nouă le încarcă la pornire. Regulile existente se aplică în
/// continuare; doar ce e necunoscut e oprit până la reconectare.
///
/// Valorile anterioare se păstrează în UserDefaults, ca să fie refăcute și
/// dacă aplicația cade în mijlocul actualizării.
///
/// Bug reparat în 2.3.5 (confirmat în log, 2026-09-20 → 09-22): `release()`
/// ștergea copia salvată chiar dacă motorul era neconectat, iar următorul
/// `engage()` salva ca „anterioară” chiar starea gardei — motorul rămânea
/// definitiv pe „blochează tot ce n-are regulă”. De aceea:
///   - copia se șterge DOAR după ce motorul confirmă preferințele refăcute
///     (răspunsul lui `updatePreferences`); altfel se reîncearcă la conectare;
///   - starea gardei nu e salvată niciodată ca „anterioară” și nici refăcută;
///   - fără nicio actualizare în curs, un motor rămas în starea gardei e readus
///     la modul normal (`releaseIfSafe`, la fiecare conectare).
@MainActor
enum UpdateGuard {
    static let savedKey = "GDCFirewall.updateGuard.previous"
    /// `engaged` | `releasing` — ridicarea cerută, dar neconfirmată de motor.
    static let stateKey = "GDCFirewall.updateGuard.state"
    private static let log = DiagnosticLog("updateguard")

    // Injectabile pentru teste.
    static var engine: UpdateGuardEngine = DaemonBridge.shared
    static var defaults: UserDefaults = .standard
    /// Actualizare în curs = etapa instalatorului nu e `.idle` SAU rulează încă
    /// extensia altei versiuni. A doua condiție acoperă cursa de la pornire:
    /// `connect()` poate ajunge la motorul vechi înainte ca `activate()` să
    /// fi trecut etapa în `.replacing` (instalare peste o versiune care rulează,
    /// sau orice actualizare, înainte ca extensia nouă să înlocuiască vechea).
    static var updateInProgress: () async -> Bool = {
        if SystemExtensionInstaller.shared.phase != .idle { return true }
        return await EngineService.foreignEngineRunning()
    }
    static var connectPollInterval: UInt64 = 200_000_000

    enum State: String { case engaged, releasing }

    /// Crește la fiecare `engage()`: o ridicare pornită înainte nu mai șterge
    /// starea unei gărzi aplicate între timp.
    private static var generation = 0

    static let guardPrefs: [String: Any] = [
        LuLu.Pref.passiveMode: true,
        LuLu.Pref.passiveModeAction: LuLu.Pref.passiveBlock,
        LuLu.Pref.passiveModeRules: LuLu.Pref.passiveRulesNo,
    ]
    static let normalPrefs: [String: Any] = [
        LuLu.Pref.passiveMode: false,
        LuLu.Pref.passiveModeAction: LuLu.Pref.passiveAllow,
        LuLu.Pref.passiveModeRules: LuLu.Pref.passiveRulesNo,
    ]

    static var state: State? {
        if let raw = defaults.string(forKey: stateKey) { return State(rawValue: raw) ?? .engaged }
        // 2.3.4 și mai vechi țineau doar copia salvată.
        return defaults.dictionary(forKey: savedKey) != nil ? .engaged : nil
    }

    static var isEngaged: Bool { state != nil }

    /// Așteaptă conexiunea cu extensia veche (max. `timeout`), apoi aplică garda.
    @discardableResult
    static func engage(timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !engine.isConnected && Date() < deadline {
            try? await Task.sleep(nanoseconds: connectPollInterval)
        }
        guard engine.isConnected, let current = await engine.preferences() else {
            log.warning("Garda de actualizare nu s-a putut aplica: extensia veche nu răspunde")
            return false
        }
        generation += 1
        if defaults.dictionary(forKey: savedKey) == nil {
            let snapshot = passiveTriple(current)
            if isEngaged || isGuard(snapshot) {
                log.warning("Motorul e deja în starea gardei, fără copie salvată — la ridicare revine la modul normal")
                defaults.set(normalPrefs, forKey: savedKey)
            } else {
                defaults.set(snapshot, forKey: savedKey)
            }
        }
        defaults.set(State.engaged.rawValue, forKey: stateKey)
        guard let reply = await engine.applyPreferences(guardPrefs), isGuard(passiveTriple(reply)) else {
            log.warning("Garda de actualizare netrimisă sau neconfirmată de motor")
            return false
        }
        log.info("Garda de actualizare activă: conexiunile necunoscute sunt blocate până la reconectare")
        return true
    }

    /// La fiecare conectare cu motorul. Cu o actualizare în curs, garda rămâne
    /// (motorul e încă cel vechi) — dacă ridicarea n-a fost deja cerută.
    static func releaseIfSafe() async {
        if let state {
            if state == .engaged, await updateInProgress() {
                log.info("Garda rămâne: actualizarea extensiei nu s-a încheiat")
                return
            }
            await release()
            return
        }
        guard !(await updateInProgress()) else { return }
        await healStuckGuard()
    }

    /// Și când înlocuirea e amânată: aplicația rămâne pe extensia veche.
    /// `true` = motorul a confirmat preferințele refăcute.
    @discardableResult
    static func release() async -> Bool {
        guard isEngaged else { return true }
        defaults.set(State.releasing.rawValue, forKey: stateKey)
        let started = generation
        let saved = defaults.dictionary(forKey: savedKey).map(passiveTriple) ?? normalPrefs
        // O copie „otrăvită” de 2.3.4 (chiar starea gardei) nu se reface.
        let target = isGuard(saved) ? normalPrefs : saved
        guard let reply = await engine.applyPreferences(target), same(passiveTriple(reply), target) else {
            log.warning("Garda de actualizare NU a fost ridicată: motorul nu a confirmat preferințele — reîncerc la următoarea conectare")
            return false
        }
        guard generation == started else {
            log.info("Ridicarea gărzii depășită: o gardă nouă a fost aplicată între timp")
            return false
        }
        defaults.removeObject(forKey: savedKey)
        defaults.removeObject(forKey: stateKey)
        log.info("Garda de actualizare ridicată: preferințele anterioare au fost refăcute și confirmate de motor")
        return true
    }

    /// Nicio gardă în evidență, nicio actualizare în curs, dar motorul e în
    /// starea gardei: rămășiță a bug-ului din 2.3.4 (sau a unei căderi).
    /// Aplicația nu are control pentru modul pasiv, deci utilizatorul n-ar
    /// avea cum ieși singur.
    private static func healStuckGuard() async {
        guard let current = await engine.preferences(), isGuard(passiveTriple(current)) else { return }
        log.warning("Motorul era blocat în starea gărzii de actualizare fără nicio actualizare în curs — revin la modul normal")
        if let reply = await engine.applyPreferences(normalPrefs), same(passiveTriple(reply), normalPrefs) {
            log.info("Modul normal refăcut și confirmat de motor")
        } else {
            log.warning("Modul normal netrimis sau neconfirmat — reîncerc la următoarea conectare")
        }
    }

    // MARK: - Tripletul modului pasiv

    static func passiveTriple(_ prefs: [String: Any]) -> [String: Any] {
        [
            LuLu.Pref.passiveMode: prefs[LuLu.Pref.passiveMode] as? Bool ?? false,
            LuLu.Pref.passiveModeAction: prefs[LuLu.Pref.passiveModeAction] as? Int ?? LuLu.Pref.passiveAllow,
            LuLu.Pref.passiveModeRules: prefs[LuLu.Pref.passiveModeRules] as? Int ?? LuLu.Pref.passiveRulesNo,
        ]
    }

    static func isGuard(_ triple: [String: Any]) -> Bool { same(triple, guardPrefs) }

    private static func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        let x = passiveTriple(a), y = passiveTriple(b)
        return x[LuLu.Pref.passiveMode] as? Bool == y[LuLu.Pref.passiveMode] as? Bool
            && x[LuLu.Pref.passiveModeAction] as? Int == y[LuLu.Pref.passiveModeAction] as? Int
            && x[LuLu.Pref.passiveModeRules] as? Int == y[LuLu.Pref.passiveModeRules] as? Int
    }
}
