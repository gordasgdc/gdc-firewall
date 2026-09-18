import Foundation

/// Limba interfeței: RO (sursa), EN, ES.
///
/// Implicit urmează limba macOS; din Setări se poate fixa una anume. O limbă
/// de sistem pe care n-o acoperim primește româna — limba produsului.
enum Lang: String, CaseIterable, Identifiable {
    case ro, en, es

    var id: String { rawValue }

    /// Numele fiecărei limbi în limba ei — nu se traduce: cine caută
    /// „Español” trebuie să-l recunoască oricare ar fi limba curentă.
    var endonym: String {
        switch self {
        case .ro: return "Română"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    /// „system” sau codul unei limbi. Citit la fiecare text, deci o schimbare
    /// se aplică imediat, fără repornire.
    static let preferenceKey = "GDCFirewall.language"
    static let systemValue = "system"

    static var current: Lang {
        let stored = UserDefaults.standard.string(forKey: preferenceKey) ?? systemValue
        if let fixed = Lang(rawValue: stored) { return fixed }
        let preferred = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "ro"
        return Lang(rawValue: String(preferred)) ?? .ro
    }
}

/// Textele interfeței. Cheia e chiar textul românesc (limba sursă);
/// traducerile stau în `Resources/<limbă>.lproj/GDC.strings`.
///
/// Tabelul se numește „GDC”, nu „Localizable”: ținta Xcode cară și catalogul
/// motorului LuLu sub acel nume. `scripts/check-l10n.sh` pică build-ul dacă o
/// cheie din cod lipsește dintr-o traducere.
enum L10n {
    static let table = "GDC"

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    static func string(_ key: String, _ lang: Lang = .current) -> String {
        // Româna e textul-cheie însuși: nu există fișier de tradus.
        guard lang != .ro,
              let path = resourceBundle.path(forResource: lang.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: table)
    }

    /// Mesajul actualizării cerute de un motor de filtrare învechit. Deliberat
    /// mai ferm decât un update obișnuit: utilizatorul rulează un filtru pe
    /// care autorii lui nu-l mai susțin.
    static func engineUpdateRequired() -> String {
        L("O nouă actualizare critică de securitate pentru motorul de filtrare este disponibilă. Rulați actualizarea pentru a menține protecția.")
    }
}

/// `L("Reguli")`, sau cu parametri: `L("Extensia nu a pornit: %@", motiv)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.string(key)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: Locale(identifier: Lang.current.rawValue), arguments: args)
}
