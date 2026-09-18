import AppKit
import Security

/// Intrările barei laterale din fereastra Reguli.
///
/// Doar ce se poate calcula din datele motorului. Categoriile Little Snitch
/// bazate pe utilizare (Recently Used, Unused), prioritate (Unnecessary
/// Priority) sau moduri de alertă (Login, Full Screen) nu au echivalent în
/// motorul LuLu — nu apar, ca să nu arate liste mereu goale.
enum SidebarItem: Hashable {
    case all, active, deny, recentChanges, temporary, unapproved
    case group(RuleGroup)
    case expired
    case redundant, identityMismatch, noIdentityCheck, missingExecutable
    case blocklist

    var title: String {
        switch self {
        case .all: return L("Toate regulile")
        case .active: return L("Active")
        case .deny: return L("Blocate")
        case .recentChanges: return L("Schimbări recente")
        case .temporary: return L("Temporare")
        case .unapproved: return L("Neaprobate")
        case .group(let group): return group.title
        case .expired: return L("Expirate")
        case .redundant: return L("Redundante")
        case .identityMismatch: return L("Identitate schimbată")
        case .noIdentityCheck: return L("Fără verificare de identitate")
        case .missingExecutable: return L("Executabil lipsă")
        case .blocklist: return "StevenBlack"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .active: return "checkmark.circle"
        case .deny: return "hand.raised"
        case .recentChanges: return "clock.arrow.circlepath"
        case .temporary: return "timer"
        case .unapproved: return "questionmark.circle"
        case .group(let group): return group.systemImage
        case .expired: return "calendar.badge.exclamationmark"
        case .redundant: return "square.on.square"
        case .identityMismatch: return "person.crop.circle.badge.exclamationmark"
        case .noIdentityCheck: return "person.crop.circle.badge.questionmark"
        case .missingExecutable: return "doc.questionmark"
        case .blocklist: return "shield.lefthalf.filled"
        }
    }

    /// Explicația din antetul listei — de ce e o regulă aici și ce faci cu ea.
    var explanation: String? {
        switch self {
        case .unapproved:
            return L("Create automat cât interfața GDC nu era pornită: motorul a permis conexiunea fără să te întrebe. Aprobă-le sau șterge-le.")
        case .expired:
            return L("Reguli cu termen depășit. Nu mai au efect — le poți șterge.")
        case .redundant:
            return L("Reguli identice cu altele deja existente. Poți păstra una singură.")
        case .identityMismatch:
            return L("Semnătura executabilului de pe disc nu mai corespunde celei din regulă. Programul a fost înlocuit sau actualizat de alt dezvoltator.")
        case .noIdentityCheck:
            return L("Reguli pentru programe nesemnate: motorul le recunoaște doar după cale, nu după semnătură.")
        case .missingExecutable:
            return L("Executabilul nu mai există la calea din regulă. Folosește „Repară calea…” dacă l-ai mutat.")
        default:
            return nil
        }
    }
}

enum RuleAnalysis {
    static let recentWindow: TimeInterval = 7 * 24 * 3600

    static func rules(for item: SidebarItem, in all: [FirewallRule], mismatches: Set<String>) -> [FirewallRule] {
        switch item {
        case .all: return all
        case .active: return all.filter { !$0.isDisabled && !$0.isExpired }
        case .deny: return all.filter { $0.action == .block }
        case .recentChanges:
            let since = Date().addingTimeInterval(-recentWindow)
            return all.filter { ($0.creation ?? .distantPast) >= since }
                .sorted { ($0.creation ?? .distantPast) > ($1.creation ?? .distantPast) }
        case .temporary: return all.filter { $0.isTemporary && !$0.isExpired }
        case .unapproved: return all.filter(\.isUnapproved)
        case .group(let group): return all.filter { $0.group == group }
        case .expired: return all.filter(\.isExpired)
        case .redundant: return redundant(in: all)
        case .identityMismatch: return all.filter { mismatches.contains($0.id) }
        case .noIdentityCheck: return all.filter { !$0.isGlobal && !$0.hasIdentity && $0.executableExists }
        case .missingExecutable: return all.filter { !$0.executableExists }
        case .blocklist: return []
        }
    }

    /// Toate regulile care repetă una deja văzută (aceeași cale, destinație,
    /// port, acțiune) — prima rămâne, restul sunt redundante.
    static func redundant(in all: [FirewallRule]) -> [FirewallRule] {
        var seen = Set<String>()
        var result: [FirewallRule] = []
        for rule in all.sorted(by: { ($0.creation ?? .distantPast) < ($1.creation ?? .distantPast) }) {
            let signature = "\(rule.enginePath)|\(rule.endpointAddr)|\(rule.endpointType)|\(rule.endpointPort)|\(rule.action.rawValue)"
            if !seen.insert(signature).inserted { result.append(rule) }
        }
        return result
    }
}

// MARK: - Verificarea identității pe disc

/// Compară semnătura ACTUALĂ a fiecărui executabil cu cea memorată în regulă
/// (ID de cod + Team ID). O diferență înseamnă că la calea aceea stă acum
/// alt program decât cel aprobat.
@MainActor
final class IdentityChecker: ObservableObject {
    static let shared = IdentityChecker()

    struct Identity: Equatable {
        let codeID: String?
        let teamID: String?
    }

    @Published private(set) var current: [String: Identity] = [:]   // cale → identitate pe disc
    @Published private(set) var mismatches: Set<String> = []          // id-uri de reguli
    private let log = DiagnosticLog("identity")

    func check(_ rules: [FirewallRule]) {
        let candidates = rules.filter { $0.hasIdentity && !$0.isGlobal && !$0.isDirectory && $0.executableExists }
        let paths = Set(candidates.map(\.enginePath))
        Task.detached(priority: .utility) {
            var found: [String: Identity] = [:]
            for path in paths { found[path] = Self.identity(at: path) }
            let result = found
            await MainActor.run {
                self.current = result
                self.mismatches = Set(candidates.filter { rule in
                    guard let now = result[rule.enginePath] else { return false }
                    return !Self.matches(rule: rule, current: now)
                }.map(\.id))
                if !self.mismatches.isEmpty {
                    self.log.warning("Identitate schimbată la \(self.mismatches.count) reguli")
                }
            }
        }
    }

    nonisolated static func matches(rule: FirewallRule, current: Identity) -> Bool {
        if let expected = rule.bundleID, expected != current.codeID { return false }
        // Pentru binarele Apple, Team ID-ul lipsește din semnătura de platformă.
        if let team = rule.teamID, team != "APPLE", team != current.teamID { return false }
        return true
    }

    nonisolated static func identity(at path: String) -> Identity {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return Identity(codeID: nil, teamID: nil) }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return Identity(codeID: nil, teamID: nil) }
        return Identity(codeID: dict[kSecCodeInfoIdentifier as String] as? String,
                        teamID: dict[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}

// MARK: - Pictograme native

/// Pictograma reală a aplicației, din NSWorkspace, cu cache. Pentru un
/// executabil dinăuntrul unui pachet .app se folosește pictograma pachetului.
enum AppIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for rule: FirewallRule) -> NSImage {
        if rule.isGlobal {
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        }
        guard let url = rule.fileURL, rule.executableExists else {
            return NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return icon(forPath: url.path)
    }

    static func icon(forPath path: String) -> NSImage {
        let target = bundlePath(containing: path) ?? path
        if let cached = cache.object(forKey: target as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: target)
        cache.setObject(image, forKey: target as NSString)
        return image
    }

    /// „/Applications/X.app/Contents/MacOS/X” → „/Applications/X.app”
    /// (cel mai exterior pachet, ca un helper să arate pictograma aplicației).
    static func bundlePath(containing path: String) -> String? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
