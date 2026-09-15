import Foundation

/// O cerere de conexiune ridicată de motor. E o structură GDC, nu una a
/// motorului: o construim din dicționarul trimis prin XPC de LuLu, exact
/// cum vine, fără să schimbăm nimic în extensie.
struct ConnectionRequest: Identifiable, Hashable {
    let id: UUID
    let processID: pid_t
    let path: String
    let bundleID: String?
    let displayName: String?
    let remoteHost: String       // nume DNS dacă există, altfel IP
    let remoteAddress: String
    let remotePort: Int
    let isAppleSigned: Bool
    let isNotarized: Bool
    let arrivedAt: Date

    var processName: String { (path as NSString).lastPathComponent }

    var risk: RiskLevel {
        if isAppleSigned { return .safe }
        if isNotarized { return .known }
        return .unknown
    }

    var friendlyName: String {
        ProcessCatalog.shared.friendlyName(processName: processName, bundleID: bundleID, displayName: displayName)
    }

    var friendlyDetail: String {
        ProcessCatalog.shared.detail(processName: processName, bundleID: bundleID)
            ?? "Acest program vrea să trimită sau să primească date pe internet."
    }

    /// Portul, tradus acolo unde traducerea chiar ajută. Restul rămân
    /// numere — mai bine un număr onest decât o etichetă inventată.
    var portDescription: String {
        switch remotePort {
        case 80: return "web (HTTP, nesecurizat)"
        case 443: return "web securizat (HTTPS)"
        case 53: return "căutare adrese (DNS)"
        case 22: return "terminal la distanță (SSH)"
        case 25, 465, 587: return "trimitere e-mail"
        case 993, 995: return "citire e-mail"
        default: return "port \(remotePort)"
        }
    }
}

/// Decizia utilizatorului, trimisă înapoi motorului.
struct AlertVerdict {
    let request: ConnectionRequest
    let action: RuleAction
    /// `false` = doar de data asta; `true` = scrie o regulă permanentă.
    let remember: Bool
    let origin: RuleOrigin
}
