import SwiftUI

/// Semaforul. E singura scară de risc din aplicație — orice ecran care
/// arată o stare de risc o ia de aici, ca să nu apară două vocabulare.
enum RiskLevel: Int, Comparable {
    case safe = 0       // verde  — semnat oficial de Apple
    case known = 1      // galben — dezvoltator identificat, notarizat
    case unknown = 2    // roșu   — nesemnat / neidentificat

    static func < (a: RiskLevel, b: RiskLevel) -> Bool { a.rawValue < b.rawValue }

    /// Culori semantice, definite o singură dată (Regula 37): niciun ecran
    /// nu scrie `.red`/`.green` direct pe un control.
    var tint: Color {
        switch self {
        case .safe: return .green
        case .known: return .yellow
        case .unknown: return .red
        }
    }

    var title: String {
        switch self {
        case .safe: return L("Sigur")
        case .known: return L("Aplicație cunoscută")
        case .unknown: return L("Neidentificat")
        }
    }

    /// Recomandarea vizibilă din alertă — textul pe care se uită un
    /// utilizator care nu știe ce e un „proces”.
    var recommendation: String {
        switch self {
        case .safe: return L("Aprobă (Recomandat)")
        case .known: return L("Verifică aplicația")
        case .unknown: return L("Blochează accesul")
        }
    }

    var explanation: String {
        switch self {
        case .safe:
            return L("Face parte din macOS și e semnat oficial de Apple. Blocarea lui poate strica funcții ale sistemului.")
        case .known:
            return L("Aplicația e semnată de un dezvoltator identificat, dar nu face parte din macOS. Aprob-o doar dacă o recunoști.")
        case .unknown:
            return L("Nu am putut identifica cine a scris acest program. Dacă nu l-ai instalat tu conștient, blochează-l.")
        }
    }

    var systemImage: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .known: return "questionmark.circle.fill"
        case .unknown: return "exclamationmark.triangle.fill"
        }
    }

    /// Butonul implicit (cel focusat) urmează recomandarea, ca un
    /// „Enter” apăsat din reflex să nu fie niciodată alegerea periculoasă.
    var defaultsToAllow: Bool { self == .safe }
}
