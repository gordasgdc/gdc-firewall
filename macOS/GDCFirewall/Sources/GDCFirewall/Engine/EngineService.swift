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
/// Deci jobul vechi se scoate ÎNAINTE de activare (root: o parolă, sau scriptul
/// actualizării automate, care rulează deja ca root).
///
/// Totul se citește fără root (`launchctl print`); doar scoaterea cere parola.
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

    enum RestartError: LocalizedError {
        case cancelled
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: return L("Actualizarea motorului a fost amânată.")
            case .failed(let detail): return L("Oprirea versiunii vechi a motorului a eșuat: %@", detail)
            }
        }
    }

    /// Scoate joburile versiunii vechi (promptul nativ de parolă de
    /// administrator). `bootout` revine după oprirea procesului (~5 s: motorul
    /// nu iese la SIGTERM). Blochează — se apelează din afara firului principal.
    static func removeJobsWithAdmin(_ labels: [String]) throws {
        let command = labels.map { "/bin/launchctl bootout system/\($0)" }.joined(separator: "; ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.contains("-128") { throw RestartError.cancelled }
            throw RestartError.failed(message.isEmpty ? L("cod %d", Int(process.terminationStatus)) : message)
        }
        log.info("Joburi scoase din launchd înainte de activare: \(labels.joined(separator: ", "))")
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
@MainActor
enum UpdateGuard {
    private static let savedKey = "GDCFirewall.updateGuard.previous"
    private static let log = DiagnosticLog("updateguard")

    static var isEngaged: Bool { UserDefaults.standard.dictionary(forKey: savedKey) != nil }

    /// Așteaptă conexiunea cu extensia veche (max. `timeout`), apoi aplică garda.
    static func engage(timeout: TimeInterval = 3) async -> Bool {
        let bridge = DaemonBridge.shared
        let deadline = Date().addingTimeInterval(timeout)
        while !bridge.isConnected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard bridge.isConnected, let current = await bridge.preferences() else {
            log.warning("Garda de actualizare nu s-a putut aplica: extensia veche nu răspunde")
            return false
        }
        if !isEngaged {
            let previous: [String: Any] = [
                LuLu.Pref.passiveMode: current[LuLu.Pref.passiveMode] as? Bool ?? false,
                LuLu.Pref.passiveModeAction: current[LuLu.Pref.passiveModeAction] as? Int ?? LuLu.Pref.passiveAllow,
                LuLu.Pref.passiveModeRules: current[LuLu.Pref.passiveModeRules] as? Int ?? LuLu.Pref.passiveRulesNo,
            ]
            UserDefaults.standard.set(previous, forKey: savedKey)
        }
        bridge.updatePreferences([
            LuLu.Pref.passiveMode: true,
            LuLu.Pref.passiveModeAction: LuLu.Pref.passiveBlock,
            LuLu.Pref.passiveModeRules: LuLu.Pref.passiveRulesNo,
        ])
        log.info("Garda de actualizare activă: conexiunile necunoscute sunt blocate până la reconectare")
        return true
    }

    /// La conectarea cu extensia CURENTĂ (nu cu cea veche, în timpul înlocuirii).
    static func releaseIfSafe() {
        guard SystemExtensionInstaller.shared.phase == .idle else { return }
        release()
    }

    /// Și când înlocuirea e amânată: aplicația rămâne pe extensia veche.
    static func release() {
        guard let previous = UserDefaults.standard.dictionary(forKey: savedKey) else { return }
        DaemonBridge.shared.updatePreferences(previous)
        UserDefaults.standard.removeObject(forKey: savedKey)
        log.info("Garda de actualizare ridicată: preferințele anterioare au fost refăcute")
    }
}
