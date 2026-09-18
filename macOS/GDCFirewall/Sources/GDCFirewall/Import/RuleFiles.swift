import AppKit
import UniformTypeIdentifiers

/// Import dintr-un fișier ales de utilizator și export de reguli.
///
/// Formatul se recunoaște după CONȚINUT, nu după extensie — un export
/// Little Snitch poate avea `.json` sau `.lsrules`, un fișier LuLu `.json`
/// sau `.plist`:
///   - JSON cu o listă `rules` la rădăcină → Little Snitch (`export-model`,
///     „File → Export Model…” sau `.lsrules`);
///   - JSON `{ cheie: [ { path, action, … } ] }` → exportul LuLu
///     („Rules → Export”);
///   - plist cu arhivă de obiecte `Rule` → `rules.plist` al LuLu.
extension RuleImporter {
    static let fileTypes: [UTType] = [.json, .propertyList]
        + ["lsrules", "xbel"].compactMap { UTType(filenameExtension: $0) }

    static func importFile(at url: URL, existing: Set<String>) throws -> ImportReport {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        let head = String(decoding: data.prefix(1024), as: UTF8.self)

        // XBEL = semne de carte de browser (XML Bookmark Exchange Language):
        // nu conține reguli de firewall, orice extensie ar avea.
        if head.contains("<xbel") {
            throw ImportError.unreadable(L("fișierul e în format XBEL (semne de carte de browser) și nu conține reguli de firewall"))
        }
        if data.starts(with: Data("bplist".utf8)) || head.contains("<plist") {
            return try importLuLu(archive: data, existing: existing)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.unreadable(L("format necunoscut"))
        }
        if let dict = json as? [String: Any], dict["rules"] is [[String: Any]] {
            return try importLittleSnitch(data: data, existing: existing)
        }
        if let dict = json as? [String: [[String: Any]]], dict.values.contains(where: { $0.first?["path"] != nil }) {
            return importLuLuJSON(dict, existing: existing)
        }
        throw ImportError.unreadable(L("format necunoscut"))
    }

    /// Exportul JSON al LuLu: doar regulile create de utilizator; cele Apple
    /// și implicite le are motorul GDC oricum.
    static func importLuLuJSON(_ root: [String: [[String: Any]]], existing: Set<String>) -> ImportReport {
        var report = ImportReport()
        var seen = existing
        for rules in root.values {
            for rule in rules {
                guard (rule["type"] as? Int) == LuLu.RuleType.user else { continue }
                if (rule["isDisabled"] as? Int ?? 0) != 0 { report.skip(L("dezactivate")); continue }
                if rule["expiration"] != nil { report.skip(L("valabile doar cât rula procesul")); continue }
                guard let path = rule["path"] as? String else { report.skip(L("fără cale")); continue }
                guard path == "*" || FileManager.default.fileExists(atPath: path) else {
                    report.skip(L("aplicații absente pe acest Mac")); continue
                }
                let addr = rule["endpointAddr"] as? String ?? "*"
                let port = rule["endpointPort"].map { "\($0)" } ?? "*"
                let action = (rule["action"] as? Int) ?? LuLu.RuleState.block
                var info: [String: Any] = [
                    LuLu.Key.path: path,
                    LuLu.Key.action: action,
                    LuLu.Key.type: LuLu.RuleType.user,
                    LuLu.Key.duration: LuLu.Duration.always,
                    LuLu.Key.endpointAddr: addr,
                    LuLu.Key.endpointPort: port,
                ]
                if let kind = rule["isEndpointAddrRegex"] as? Int, kind != LuLu.EndpointType.exact {
                    info[LuLu.Key.endpointAddrIsRegex] = kind
                }
                let signature = DaemonBridge.signature(path: path, addr: addr, port: port, action: action)
                if seen.insert(signature).inserted { report.rules.append(info) } else { report.duplicates += 1 }
            }
        }
        return report
    }
}

/// Export în formatul public `.lsrules` (Little Snitch): regulile se pot
/// importa înapoi în GDC Firewall sau în Little Snitch.
enum RuleExporter {
    struct Result {
        let data: Data
        let exported: Int
        let skipped: Int
    }

    static func lsrules(_ rules: [FirewallRule], name: String) -> Result {
        var entries: [[String: Any]] = []
        var skipped = 0
        for rule in rules {
            var entry: [String: Any] = [
                "process": rule.isGlobal ? "any" : rule.enginePath,
                "action": rule.action == .allow ? "allow" : "deny",
                "direction": "outgoing",
            ]
            if rule.endpointPort != "*" { entry["ports"] = rule.endpointPort }
            switch (rule.endpointAddr, rule.endpointType) {
            case ("*", _):
                entry["remote"] = "any"
            case (let addr, LuLu.EndpointType.exact):
                entry[addr.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) ? "remote-addresses" : "remote-hosts"] = addr
            case (let addr, LuLu.EndpointType.cidr):
                entry["remote-addresses"] = addr
            case (let addr, LuLu.EndpointType.regex):
                // Doar forma produsă de importul Little Snitch („domeniu +
                // subdomenii”) are echivalent; o expresie oarecare, nu.
                guard let domain = domain(fromRegex: addr) else { skipped += 1; continue }
                entry["remote-domains"] = domain
            default:
                skipped += 1
                continue
            }
            if rule.isDisabled { entry["disabled"] = true }
            entries.append(entry)
        }
        let document: [String: Any] = [
            "name": name,
            "description": L("Exportat din GDC Firewall"),
            "rules": entries,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return Result(data: data, exported: entries.count, skipped: skipped)
    }

    /// `^(.+\.)?example\.com$` → `example.com`.
    static func domain(fromRegex pattern: String) -> String? {
        let prefix = #"^(.+\.)?"#
        guard pattern.hasPrefix(prefix), pattern.hasSuffix("$") else { return nil }
        let escaped = pattern.dropFirst(prefix.count).dropLast()
        let domain = escaped.replacingOccurrences(of: #"\."#, with: ".")
        return domain.contains("\\") ? nil : domain
    }

    /// Panoul de salvare + scrierea fișierului. Întoarce mesajul pentru utilizator.
    @MainActor
    static func save(_ rules: [FirewallRule], suggestedName: String) -> String? {
        let result = lsrules(rules, name: suggestedName)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName + ".lsrules"
        panel.allowedContentTypes = [UTType(filenameExtension: "lsrules") ?? .json]
        panel.message = L("Regulile se pot importa înapoi în GDC Firewall sau în Little Snitch.")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try result.data.write(to: url, options: .atomic)
            DiagnosticLog("export").info("Export: \(result.exported) reguli în \(url.path), sărite \(result.skipped)")
            return result.skipped == 0
                ? L("Exportate: %d", result.exported)
                : L("Exportate: %d · fără echivalent: %d", result.exported, result.skipped)
        } catch {
            return error.localizedDescription
        }
    }
}
