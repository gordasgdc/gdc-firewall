import Foundation

/// Textele care trebuie să existe în toate cele trei limbi ale portofoliului
/// (RO/EN/ES).
///
/// Interfața aplicației e deliberat doar în română — asta e promisiunea
/// produsului. Aici stau STRICT mesajele care ajung și în altă parte decât în
/// fereastra aplicației: ghidul PDF și avertismentele critice de securitate,
/// pe care un utilizator trebuie să le înțeleagă chiar dacă nu citește
/// română. Nu e un sistem de localizare complet și nu pretinde să fie.
enum Lang: String, CaseIterable {
    case ro, en, es

    /// Limba preferată a sistemului, redusă la cele trei pe care le acoperim.
    /// Orice altceva primește română — e limba produsului, nu engleza.
    static var current: Lang {
        let preferred = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "ro"
        return Lang(rawValue: String(preferred)) ?? .ro
    }
}

enum L10n {
    /// Mesajul afișat când actualizarea e cerută de motorul de filtrare
    /// învechit, nu de o versiune nouă a interfeței. Formularea e
    /// deliberat mai fermă decât la un update obișnuit: aici utilizatorul
    /// rulează un filtru pe care autorii lui nu-l mai susțin.
    static let engineUpdateRequired: [Lang: String] = [
        .ro: "O nouă actualizare critică de securitate pentru motorul de filtrare este disponibilă. Rulați actualizarea pentru a menține protecția.",
        .en: "A critical security update for the filtering engine is available. Run the update to maintain protection.",
        .es: "Una actualización de seguridad crítica para el motor de filtrado está disponible. Ejecute la actualización para mantener la protección."
    ]

    static func engineUpdateRequired(_ lang: Lang = .current) -> String {
        // Română ca ultimă plasă de siguranță: un dicționar incomplet nu
        // trebuie să producă niciodată un pop-up gol.
        engineUpdateRequired[lang] ?? engineUpdateRequired[.ro]!
    }
}
