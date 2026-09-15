import Foundation

/// Acțiunea unei reguli. Valorile brute corespund 1:1 constantelor
/// `RULE_STATE_*` din motorul LuLu — modelul GDC le traduce, nu le redefinește.
enum RuleAction: Int, Codable {
    case block = 0
    case allow = 1

    var label: String { self == .allow ? "Permis" : "Blocat" }
}

/// Cine a creat regula. Distincția contează în UI: regulile scrise de
/// Auto-Pilot se pot revizui în bloc, cele scrise de utilizator nu se ating.
enum RuleOrigin: Int, Codable {
    case user = 0        // utilizatorul a răspuns la o alertă
    case autoPilot = 1   // Modul Silențios a aprobat automat un proces Apple
    case baseline = 2    // regulă de bază, instalată odată cu aplicația

    var label: String {
        switch self {
        case .user: return "Decizia ta"
        case .autoPilot: return "Aprobare inteligentă"
        case .baseline: return "Regulă de bază"
        }
    }
}

/// Categoriile din Rules Manager. Ordinea e ordinea de afișare.
enum RuleCategory: String, Codable, CaseIterable, Identifiable {
    case verifiedApps = "Aplicații Verificate"
    case systemServices = "Servicii Sistem"
    case blocked = "Reguli Blocate"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .verifiedApps: return "checkmark.seal"
        case .systemServices: return "gearshape.2"
        case .blocked: return "hand.raised"
        }
    }
}

/// O regulă, așa cum o vede interfața GDC. `enginePath` e cheia sub care
/// motorul o ține — singurul câmp care trebuie să rămână identic cu motorul.
struct FirewallRule: Identifiable, Codable, Hashable {
    let id: String
    let enginePath: String          // cale absolută a binarului
    let bundleID: String?
    var friendlyName: String        // nume intuitiv în română
    var action: RuleAction
    var origin: RuleOrigin
    var isAppleSigned: Bool
    var isNotarized: Bool
    var lastConnection: Date?
    var connectionCount: Int

    var category: RuleCategory {
        if action == .block { return .blocked }
        return isAppleSigned ? .systemServices : .verifiedApps
    }

    /// Numele tehnic, pentru cei care vor să vadă ce rulează de fapt.
    var processName: String { (enginePath as NSString).lastPathComponent }
}
