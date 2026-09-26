import SwiftUI

/// Semaforul. E singura scară de risc din aplicație — orice ecran care
/// arată o stare de risc o ia de aici, ca să nu apară două vocabulare.
///
/// Scara descrie DOAR ce s-a observat despre semnătura programului. O
/// semnătură Apple nu dovedește că o conexiune e sigură, iar lipsa ei nu
/// dovedește că programul e rău intenționat — de aceea textele separă:
///   - `identity`       — faptul observat (cine a semnat);
///   - `assessment`     — estimarea riscului, numită explicit estimare;
///   - `explanation`    — de ce contează;
///   - `recommendation` — ce poate face utilizatorul.
enum RiskLevel: Int, Comparable, CaseIterable {
    case appleSigned = 0         // semnat de Apple, componentă macOS
    case identifiedDeveloper = 1 // Developer ID / App Store
    case unverified = 2          // fără semnătură validă

    static func < (a: RiskLevel, b: RiskLevel) -> Bool { a.rawValue < b.rawValue }

    /// Clasificarea, pură: doar din ce raportează motorul despre semnătură.
    static func classify(isAppleSigned: Bool, isNotarized: Bool) -> RiskLevel {
        if isAppleSigned { return .appleSigned }
        if isNotarized { return .identifiedDeveloper }
        return .unverified
    }

    var tone: StatusTone {
        switch self {
        case .appleSigned: return .success
        case .identifiedDeveloper: return .attention
        case .unverified: return .error
        }
    }

    /// Culori semantice, definite o singură dată (Regula 37).
    var tint: Color { tone.tint }

    /// Faptul observat, într-o formulare pe care o înțelege oricine.
    var identity: String {
        switch self {
        case .appleSigned: return L("Componentă macOS semnată de Apple")
        case .identifiedDeveloper: return L("Dezvoltator identificat")
        case .unverified: return L("Semnătură lipsă sau invalidă")
        }
    }

    /// Estimarea — prezentată ca estimare, nu ca verdict.
    var assessment: String {
        switch self {
        case .appleSigned: return L("Risc estimat: scăzut")
        case .identifiedDeveloper: return L("Risc estimat: depinde dacă recunoști aplicația")
        case .unverified: return L("Risc estimat: ridicat")
        }
    }

    var explanation: String {
        switch self {
        case .appleSigned:
            return L("Face parte din macOS. Blocarea lui poate strica funcții ale sistemului.")
        case .identifiedDeveloper:
            return L("Semnătura arată cine a publicat aplicația, dar nu ce face. Nu face parte din macOS.")
        case .unverified:
            return L("Fără o semnătură validă nu se poate verifica cine a scris programul sau dacă a fost modificat.")
        }
    }

    /// Recomandarea vizibilă din alertă — textul pe care se uită un
    /// utilizator care nu știe ce e un „proces”.
    var recommendation: String {
        switch self {
        case .appleSigned: return L("Recomandare: permite")
        case .identifiedDeveloper: return L("Recomandare: permite doar dacă recunoști aplicația")
        case .unverified: return L("Recomandare: blochează, dacă nu l-ai instalat tu")
        }
    }

    var systemImage: String {
        switch self {
        case .appleSigned: return "checkmark.shield.fill"
        case .identifiedDeveloper: return "questionmark.circle.fill"
        case .unverified: return "exclamationmark.triangle.fill"
        }
    }

    /// Butonul implicit (cel focusat) urmează recomandarea, ca un
    /// „Enter” apăsat din reflex să nu fie niciodată alegerea periculoasă.
    /// NESCHIMBAT față de 2.3.5 (acoperit de teste).
    var defaultsToAllow: Bool { self == .appleSigned }
}
