import AppKit
import Foundation
import os.log

/// Un alt firewall găsit pe Mac, la prima configurare.
///
/// GDC NU îl poate opri: macOS nu lasă o aplicație să modifice filtrul de
/// rețea sau extensia altui producător. Îi importăm regulile și îi arătăm
/// utilizatorului exact unde îl oprește el.
struct ForeignFirewall: Identifiable, Equatable {
    enum Kind: String {
        case littleSnitch
        case lulu
    }

    let kind: Kind
    var id: String { kind.rawValue }
    let name: String
    /// Starea extensiei de rețea, cum o scrie `systemextensionsctl list`
    /// („activated enabled”, „activated waiting for user”); nil = neinstalată.
    let extensionState: String?
    let appURL: URL?

    /// Filtrează efectiv conexiunile acum — două filtre active înseamnă
    /// alerte duble pentru aceeași conexiune.
    var isFiltering: Bool { extensionState == "activated enabled" }

    var statusText: String {
        switch extensionState {
        case "activated enabled": return L("Activ — filtrează conexiunile acum")
        case .some(let state) where state.contains("waiting for user"): return L("Instalat, dar neaprobat în Setări")
        case .some: return L("Extensie instalată, inactivă")
        case .none: return appURL != nil ? L("Aplicație instalată, fără extensie activă") : L("Doar reguli rămase pe disc")
        }
    }

    /// Unde se oprește, în cuvintele interfeței fiecărui produs.
    var disableInstructions: String {
        switch kind {
        case .littleSnitch:
            return L("În Little Snitch: iconița din bara de meniu → comutatorul „Network Filter” pe Off. Pentru a-l scoate de tot: Little Snitch → meniul aplicației → Uninstall.")
        case .lulu:
            return L("În LuLu: iconița din bara de meniu → Preferences → „Disable” (sau „Uninstall” pentru eliminare). Alternativ: Setări de sistem → Rețea → Filtre, unde poți opri filtrul LuLu.")
        }
    }
}

enum ForeignFirewalls {
    private static let log = DiagnosticLog("import")

    static let luluRulesURL = URL(fileURLWithPath: "/Library/Objective-See/LuLu/rules.plist")
    static let littleSnitchCLI = "Contents/Components/littlesnitch"

    // MARK: - Detectare

    /// Rulează `systemextensionsctl list` (nu cere root) și caută aplicațiile.
    /// Se apelează din afara firului principal: procesul extern durează.
    static func detect() -> [ForeignFirewall] {
        let extensions = systemExtensionStates()
        var found: [ForeignFirewall] = []

        let lsApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "at.obdev.littlesnitch")
        let lsState = extensions["at.obdev.littlesnitch.networkextension"]
        if lsApp != nil || lsState != nil {
            found.append(ForeignFirewall(kind: .littleSnitch, name: "Little Snitch",
                                         extensionState: lsState, appURL: lsApp))
        }

        let luluApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.objective-see.lulu.app")
        let luluState = extensions["com.objective-see.lulu.extension"]
        if luluApp != nil || luluState != nil || FileManager.default.fileExists(atPath: luluRulesURL.path) {
            found.append(ForeignFirewall(kind: .lulu, name: "LuLu",
                                         extensionState: luluState, appURL: luluApp))
        }
        return found
    }

    /// { bundle ID extensie: stare }. Aceeași extensie poate apărea de mai
    /// multe ori (o versiune veche „waiting to uninstall”) — contează cea activă.
    private static func systemExtensionStates() -> [String: String] {
        guard let output = run("/usr/bin/systemextensionsctl", ["list"]) else { return [:] }
        var states: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let text = String(line)
            guard let open = text.lastIndex(of: "["), let close = text.lastIndex(of: "]"), open < close else { continue }
            let state = String(text[text.index(after: open)..<close])
            for id in ["at.obdev.littlesnitch.networkextension", "com.objective-see.lulu.extension"]
            where text.contains(id) {
                if states[id] == nil || state.hasPrefix("activated") { states[id] = state }
            }
        }
        return states
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
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Import

/// Rezultatul unui import, spus utilizatorului în cifre, cu motivele
/// pentru care o regulă n-a putut fi preluată — nimic sărit în tăcere.
struct ImportReport {
    var rules: [[String: Any]] = []
    var duplicates = 0
    var skipped: [String: Int] = [:]

    mutating func skip(_ reason: String) { skipped[reason, default: 0] += 1 }

    /// „Importate: 100 · Existau deja: 13 · Sărite: aplicații absente pe
    /// acest Mac (107)” — forma „etichetă: număr” ocolește acordul la plural,
    /// diferit în fiecare limbă. Motivele sunt deja traduse la `skip`.
    var summary: String {
        var parts = [L("Importate: %d", rules.count)]
        if duplicates > 0 { parts.append(L("Existau deja: %d", duplicates)) }
        let reasons = skipped.sorted { $0.value > $1.value }.map { "\($0.key) (\($0.value))" }
        if !reasons.isEmpty { parts.append(L("Sărite: %@", reasons.joined(separator: ", "))) }
        return parts.joined(separator: " · ")
    }
}

enum RuleImporter {
    private static let log = DiagnosticLog("import")

    enum ImportError: LocalizedError {
        case unreadable(String)
        case cancelled
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let detail): return L("Nu pot citi regulile: %@", detail)
            case .cancelled: return L("Import anulat.")
            case .exportFailed(let detail): return L("Exportul din Little Snitch a eșuat: %@", detail)
            }
        }
    }

    // MARK: LuLu

    /// Citește direct `rules.plist` al LuLu (lizibil fără root). Formatul e
    /// al motorului nostru — aceeași arhivă `Rule` — deci nu e nicio
    /// conversie, doar filtrare: numai regulile create de utilizator, fără
    /// cele Apple/implicite (motorul GDC le are pe ale lui) și fără cele
    /// pasive, create automat când nu era nimeni să răspundă la alertă.
    static func importLuLu(existing: Set<String>) throws -> ImportReport {
        let data: Data
        do {
            data = try Data(contentsOf: ForeignFirewalls.luluRulesURL)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        let allowed: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self,
                                   NSSet.self, NSMutableSet.self, NSDate.self]
            + (NSClassFromString("Rule").map { [$0] } ?? [])
        guard let root = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowed, from: data) as? [String: Any] else {
            throw ImportError.unreadable(L("format necunoscut"))
        }

        var report = ImportReport()
        var seen = existing
        for (_, value) in root {
            guard let entry = value as? [String: Any], let objects = entry["rules"] as? [NSObject] else { continue }
            for rule in objects {
                let type = (rule.value(forKey: "type") as? NSNumber)?.intValue
                guard type == LuLu.RuleType.user else { continue }
                if (rule.value(forKey: "isDisabled") as? NSNumber)?.boolValue == true { report.skip(L("dezactivate")); continue }
                if rule.value(forKey: "pid") != nil { report.skip(L("valabile doar cât rula procesul")); continue }
                if let expiration = rule.value(forKey: "expiration") as? Date, expiration < Date() { report.skip(L("expirate")); continue }

                guard let path = rule.value(forKey: "path") as? String else { report.skip(L("fără cale")); continue }
                guard path.hasSuffix("*") || FileManager.default.fileExists(atPath: path) else {
                    report.skip(L("aplicații absente pe acest Mac")); continue
                }
                let addr = rule.value(forKey: "endpointAddr") as? String ?? "*"
                let port = rule.value(forKey: "endpointPort") as? String ?? "*"
                let action = (rule.value(forKey: "action") as? NSNumber)?.intValue ?? LuLu.RuleState.block

                var info: [String: Any] = [
                    LuLu.Key.path: path,
                    LuLu.Key.action: action,
                    LuLu.Key.type: LuLu.RuleType.user,
                    LuLu.Key.duration: LuLu.Duration.always,
                    LuLu.Key.endpointAddr: addr,
                    LuLu.Key.endpointPort: port,
                ]
                if let kind = (rule.value(forKey: "isEndpointAddrRegex") as? NSNumber)?.intValue, kind != LuLu.EndpointType.exact {
                    info[LuLu.Key.endpointAddrIsRegex] = kind
                }
                if let proto = rule.value(forKey: "protocol") as? NSNumber { info[LuLu.Key.protocol] = proto }
                if let scope = rule.value(forKey: "scope") as? NSNumber { info[LuLu.Key.scope] = scope }

                add(info, path: path, addr: addr, port: port, action: action, to: &report, seen: &seen)
            }
        }
        log.info("Import LuLu: \(report.summary)")
        return report
    }

    // MARK: Little Snitch

    /// `littlesnitch export-model` cere root, deci trece prin promptul nativ
    /// de parolă de administrator — același mecanism ca actualizarea automată.
    /// Blochează până termină: se apelează din afara firului principal.
    static func exportLittleSnitchModel(appURL: URL) throws -> Data {
        let cli = appURL.appendingPathComponent(ForeignFirewalls.littleSnitchCLI).path
        guard FileManager.default.isExecutableFile(atPath: cli) else {
            throw ImportError.exportFailed(L("nu găsesc utilitarul littlesnitch în aplicație"))
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdcfirewall-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("littlesnitch-model.json")

        // Fișierul iese deținut de root; chmod ca să-l putem citi noi.
        let shell = "'\(cli)' export-model '\(out.path)' && chmod 644 '\(out.path)'"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.contains("-128") { throw ImportError.cancelled }
            throw ImportError.exportFailed(message.isEmpty ? L("cod %d", Int(process.terminationStatus)) : message)
        }
        do {
            return try Data(contentsOf: out)
        } catch {
            throw ImportError.exportFailed(error.localizedDescription)
        }
    }

    /// Acceptă atât exportul complet (`export-model`), cât și un fișier
    /// `.lsrules` salvat manual din Little Snitch. Câmpurile urmează formatul
    /// public `.lsrules` (process, action, direction, remote-*, ports, protocol).
    ///
    /// Se iau regulile de la rădăcina documentului (ale utilizatorului).
    /// Grupurile de reguli abonate (rule groups, blocklists) se ignoră: sunt
    /// ale furnizorilor lor, nu ale utilizatorului.
    static func importLittleSnitch(data: Data, existing: Set<String>) throws -> ImportReport {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.unreadable(L("fișierul nu e JSON"))
        }
        guard let rules = json["rules"] as? [[String: Any]] else {
            throw ImportError.unreadable(L("fișierul nu conține o listă „rules” la rădăcină"))
        }

        var report = ImportReport()
        var seen = existing
        for rule in rules {
            if rule["disabled"] as? Bool == true { report.skip(L("dezactivate")); continue }
            if (rule["direction"] as? String ?? "outgoing") != "outgoing" { report.skip(L("pentru conexiuni de intrare")); continue }
            if rule["via"] != nil { report.skip(L("de tip „via”")); continue }

            let action: Int
            switch rule["action"] as? String {
            case "allow": action = LuLu.RuleState.allow
            case "deny": action = LuLu.RuleState.block
            default: report.skip(L("„întreabă”")); continue
            }

            let process = rule["process"] as? String ?? "any"
            let path = process == "any" ? "*" : process
            guard path == "*" || FileManager.default.fileExists(atPath: path) else {
                report.skip(L("aplicații absente pe acest Mac")); continue
            }

            let portValue = rule["ports"].map { "\($0)" } ?? "any"
            guard !portValue.contains("-"), !portValue.contains(",") else { report.skip(L("cu interval de porturi")); continue }
            let port = portValue == "any" ? "*" : portValue

            var proto: Int?
            switch rule["protocol"] as? String {
            case nil, "any": proto = nil
            case "tcp": proto = Int(IPPROTO_TCP)
            case "udp": proto = Int(IPPROTO_UDP)
            default: report.skip(L("cu alt protocol decât TCP/UDP")); continue
            }

            guard let endpoints = endpoints(of: rule, report: &report) else { continue }
            for (addr, kind) in endpoints {
                var info: [String: Any] = [
                    LuLu.Key.path: path,
                    LuLu.Key.action: action,
                    LuLu.Key.type: LuLu.RuleType.user,
                    LuLu.Key.duration: LuLu.Duration.always,
                    LuLu.Key.endpointAddr: addr,
                    LuLu.Key.endpointPort: port,
                ]
                if kind != LuLu.EndpointType.exact { info[LuLu.Key.endpointAddrIsRegex] = kind }
                if let proto { info[LuLu.Key.protocol] = proto }
                add(info, path: path, addr: addr, port: port, action: action, to: &report, seen: &seen)
            }
        }
        log.info("Import Little Snitch: \(report.summary)")
        return report
    }

    /// O regulă Little Snitch poate numi mai multe destinații; motorul are o
    /// destinație per regulă, deci devin mai multe reguli.
    private static func endpoints(of rule: [String: Any], report: inout ImportReport) -> [(String, Int)]? {
        func list(_ key: String) -> [String] {
            if let one = rule[key] as? String { return [one] }
            return rule[key] as? [String] ?? []
        }
        var result: [(String, Int)] = []
        for host in list("remote-hosts") {
            result.append((host, LuLu.EndpointType.exact))
        }
        // Little Snitch: un domeniu acoperă și subdomeniile lui.
        for domain in list("remote-domains") {
            let escaped = NSRegularExpression.escapedPattern(for: domain)
            result.append(("^(.+\\.)?\(escaped)$", LuLu.EndpointType.regex))
        }
        for address in list("remote-addresses") {
            if address.contains("-") { report.skip(L("cu interval de adrese")); continue }
            result.append((address, address.contains("/") ? LuLu.EndpointType.cidr : LuLu.EndpointType.exact))
        }
        if let remote = rule["remote"] as? String {
            guard remote == "any" else { report.skip(L("cu destinație specială (rețea locală, Bonjour…)")); return nil }
            result.append(("*", LuLu.EndpointType.exact))
        }
        if result.isEmpty {
            // Destinații numite, dar niciuna convertibilă: „orice destinație”
            // ar lărgi regula — un „blochează intervalul X” ar bloca tot.
            let named = ["remote-hosts", "remote-domains", "remote-addresses", "remote"].contains { rule[$0] != nil }
            if named { return nil }
            result.append(("*", LuLu.EndpointType.exact))
        }
        return result
    }

    private static func add(_ info: [String: Any], path: String, addr: String, port: String, action: Int,
                            to report: inout ImportReport, seen: inout Set<String>) {
        let signature = DaemonBridge.signature(path: path, addr: addr, port: port, action: action)
        guard seen.insert(signature).inserted else {
            report.duplicates += 1
            return
        }
        report.rules.append(info)
    }
}
