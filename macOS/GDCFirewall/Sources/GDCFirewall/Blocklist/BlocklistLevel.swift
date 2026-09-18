import Foundation

/// Cele trei nivele predefinite. Fiecare nivel ADAUGĂ peste cel de
/// dinaintea lui — nu sunt trei liste paralele, ci trei straturi, exact
/// cum le împarte și proiectul StevenBlack prin „extensii”.
enum BlocklistLevel: String, CaseIterable, Identifiable, Codable {
    case minim
    case mediu
    case maxim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minim: return L("Minim (Recomandat)")
        case .mediu: return L("Mediu")
        case .maxim: return L("Maxim (Pornografie & Pariuri)")
        }
    }

    var summary: String {
        switch self {
        case .minim: return L("Blochează doar domeniile confirmate de malware, phishing și telemetrie agresivă.")
        case .mediu: return L("Adaugă blocarea reclamelor comune și a scripturilor de urmărire.")
        case .maxim: return L("Adaugă conținutul pentru adulți și site-urile de jocuri de noroc.")
        }
    }

    /// Variantele oficiale StevenBlack. Fiecare URL e o listă COMPLETĂ
    /// (conține și straturile de sub ea), deci se descarcă exact una
    /// singură — cea a celui mai înalt nivel activ.
    var sourceURL: URL {
        switch self {
        case .minim:
            return URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!
        case .mediu:
            return URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts")!
        case .maxim:
            return URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-gambling/hosts")!
        }
    }

    /// Ordinea de acoperire: `maxim` include `mediu`, care include `minim`.
    var rank: Int {
        switch self {
        case .minim: return 0
        case .mediu: return 1
        case .maxim: return 2
        }
    }
}
