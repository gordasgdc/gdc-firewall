import Foundation

/// Starea aplicației așa cum o arată bara de meniu: text, simbol și ton.
/// Model pur — derivat doar din starea extensiei, etapa de actualizare și
/// legătura cu motorul — ca maparea să fie testată fără interfață.
///
/// Fiecare stare are o FORMĂ proprie de simbol (nu doar altă culoare): iconul
/// din bara de meniu e monocrom, deci forma e singurul semnal vizibil.
enum MenuBarStatus: Equatable {
    case protected           // filtrul rulează și interfața e conectată
    case needsApproval       // utilizatorul trebuie să aprobe extensia
    case activating          // cererea de activare e în curs
    case reconnecting        // regulile se aplică, dar interfața nu e conectată
    case filterOff           // extensie instalată, filtrare oprită
    case updating            // extensia nouă înlocuiește versiunea veche
    case rebootRequired      // actualizarea se finalizează doar la repornire
    case failed(String)      // extensia nu a pornit
    case stopped             // motor oprit / stare necunoscută

    /// Aceeași ordine de priorități ca înainte de extragere (2.3.5): etapa de
    /// actualizare, apoi filtrul oprit, apoi conexiunea, apoi extensia.
    static func resolve(state: SystemExtensionInstaller.State,
                        phase: SystemExtensionInstaller.Phase,
                        isConnected: Bool) -> MenuBarStatus {
        switch phase {
        case .replacing: return .updating
        case .needsReboot: return .rebootRequired
        case .idle: break
        }
        if state == .filterOff { return .filterOff }
        if isConnected { return .protected }
        switch state {
        case .active: return .reconnecting
        case .requesting: return .activating
        case .needsApproval: return .needsApproval
        case .failed(let reason): return .failed(reason)
        case .unknown, .filterOff: return .stopped
        }
    }

    var text: String {
        switch self {
        case .protected: return L("Protecție activă")
        case .needsApproval: return L("Aprobă extensia în Setări de sistem")
        case .activating: return L("Se activează extensia…")
        case .reconnecting: return L("Se reconectează la motor…")
        case .filterOff: return L("Filtrare oprită")
        case .updating: return L("Se actualizează motorul de filtrare…")
        case .rebootRequired: return L("Repornește Mac-ul pentru a finaliza actualizarea")
        case .failed(let reason): return L("Extensia nu a pornit: %@", reason)
        case .stopped: return L("Motor oprit")
        }
    }

    /// Simbolul din bara de meniu (template, monocrom). Toate există din
    /// SF Symbols 2 (macOS 11), sub minimul aplicației.
    var symbol: String {
        switch self {
        case .protected: return "checkmark.shield.fill"
        case .needsApproval: return "exclamationmark.shield.fill"
        case .activating, .reconnecting: return "shield.lefthalf.filled"
        case .filterOff: return "shield.slash"
        case .updating: return "arrow.triangle.2.circlepath"
        case .rebootRequired: return "restart.circle"
        case .failed, .stopped: return "xmark.shield.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .protected: return .success
        case .needsApproval, .rebootRequired: return .attention
        case .activating, .reconnecting, .updating: return .degraded
        case .filterOff: return .neutral
        case .failed, .stopped: return .error
        }
    }

    /// Filtrul blochează efectiv conexiunile? (Reconectarea: da — regulile se
    /// aplică în continuare în motor, doar interfața lipsește.)
    var isFiltering: Bool {
        switch self {
        case .protected, .reconnecting: return true
        default: return false
        }
    }

    /// Ce aude VoiceOver pe iconul din bara de meniu.
    var accessibilityLabel: String { L("GDC Firewall: %@", text) }
}
