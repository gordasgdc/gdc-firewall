import Foundation

/// Acțiunea unei reguli. Valorile brute corespund 1:1 constantelor
/// `RULE_STATE_*` din motorul LuLu — modelul GDC le traduce, nu le redefinește.
enum RuleAction: Int, Codable {
    // Valorile sunt RULE_STATE_BLOCK / RULE_STATE_ALLOW (consts.h:87-90).
    case block = 0
    case allow = 1

    var label: String { self == .allow ? L("Permis") : L("Blocat") }
}

/// Cine a creat regula. Distincția contează în UI: regulile scrise de
/// Auto-Pilot se pot revizui în bloc, cele scrise de utilizator nu se ating.
enum RuleOrigin: Int, Codable {
    case user = 0        // utilizatorul a răspuns la o alertă
    case autoPilot = 1   // Modul Silențios a aprobat automat un proces Apple
    case baseline = 2    // regulă de bază, instalată odată cu aplicația

    var label: String {
        switch self {
        case .user: return L("Decizia ta")
        case .autoPilot: return L("Aprobare inteligentă")
        case .baseline: return L("Regulă de bază")
        }
    }
}

/// Categoriile din Rules Manager. Ordinea e ordinea de afișare.
enum RuleCategory: String, Codable, CaseIterable, Identifiable {
    case verifiedApps = "Aplicații Verificate"
    case systemServices = "Servicii Sistem"
    case blocked = "Reguli Blocate"

    /// `rawValue` e identitatea categoriei; pe ecran apare traducerea.
    /// Literale, nu `L(rawValue)`: check-l10n.sh vede doar cheile scrise în cod.
    var title: String {
        switch self {
        case .verifiedApps: return L("Aplicații Verificate")
        case .systemServices: return L("Servicii Sistem")
        case .blocked: return L("Reguli Blocate")
        }
    }

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
    let uuid: String                // uuid-ul regulii din motor
    let enginePath: String          // cale absolută a binarului
    /// Cheia din dicționarul de reguli al motorului — de regulă
    /// „semnătură:autoritate”, nu calea. `deleteRule` o cere pe asta.
    let engineKey: String
    let endpointAddr: String
    let endpointPort: String
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

    /// Construiește regula dintr-un obiect `Rule` al motorului, citit prin
    /// KVC. Stratul GDC nu redeclară clasa motorului: dacă un câmp dispare
    /// acolo, aici primim `nil` și sărim regula, în loc să crăpăm.
    init?(engineRule object: AnyObject, path: String, key: String) {
        guard let uuid = object.value(forKey: "uuid") as? String else { return nil }
        let name = object.value(forKey: "name") as? String
        let type = (object.value(forKey: "type") as? NSNumber)?.intValue ?? LuLu.RuleType.default
        let state = (object.value(forKey: "action") as? NSNumber)?.intValue ?? LuLu.RuleState.block
        let signing = object.value(forKey: "csInfo") as? [AnyHashable: Any]
        let signer = (signing?[LuLu.Key.signer] as? Int) ?? LuLu.Signer.none

        self.uuid = uuid
        // Un binar poate avea mai multe reguli (câte una per endpoint), deci
        // cheia de identitate în listă e uuid-ul, nu calea.
        self.id = uuid
        self.enginePath = path
        self.engineKey = key
        self.endpointAddr = object.value(forKey: "endpointAddr") as? String ?? "*"
        self.endpointPort = object.value(forKey: "endpointPort") as? String ?? "*"
        self.bundleID = signing?[LuLu.Key.signingID] as? String
        self.action = RuleAction(rawValue: state) ?? .block
        self.isAppleSigned = (type == LuLu.RuleType.apple) || (signer == LuLu.Signer.apple)
        self.isNotarized = (signer == LuLu.Signer.appStore || signer == LuLu.Signer.devID)
        self.origin = {
            switch type {
            case LuLu.RuleType.user: return .user
            case LuLu.RuleType.apple: return .autoPilot
            default: return .baseline
            }
        }()
        self.friendlyName = ProcessCatalog.shared.friendlyName(
            processName: (path as NSString).lastPathComponent,
            bundleID: self.bundleID,
            displayName: name
        )
        self.lastConnection = nil
        self.connectionCount = 0
    }
}
