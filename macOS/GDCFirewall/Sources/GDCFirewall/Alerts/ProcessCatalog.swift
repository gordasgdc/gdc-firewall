import Foundation

/// Traduce procesele de sistem brute în limbaj pe care îl înțelege cineva
/// care nu programează. Sursa e `ProcessDictionary.json` (resursă în bundle),
/// nu cod — ca să poată fi extinsă fără recompilare.
final class ProcessCatalog {
    static let shared = ProcessCatalog()

    struct Entry: Decodable {
        let name: String
        let detail: String
    }

    private struct Payload: Decodable {
        let entries: [String: Entry]
    }

    private let entries: [String: Entry]

    private init() {
        // Aceleași surse, două ambalaje. În pachetul SPM (harnașamentul de
        // dezvoltare a interfeței) resursa stă în `Bundle.module`; în ținta
        // Xcode integrată cu motorul, `Bundle.module` nici nu există ca
        // simbol, deci verificarea trebuie făcută la compilare, nu la rulare.
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "ProcessDictionary", withExtension: "json")
            ?? Bundle.main.url(forResource: "ProcessDictionary", withExtension: "json")
        #else
        let url = Bundle.main.url(forResource: "ProcessDictionary", withExtension: "json")
        #endif
        guard let url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            entries = [:]
            return
        }
        entries = payload.entries
    }

    /// Caută după numele binarului, apoi după ultimul segment al bundle ID-ului.
    /// Dacă nu găsește nimic, întoarce `nil` — apelantul decide fallback-ul,
    /// ca să nu inventăm aici un text care arată ca o traducere reală.
    func lookup(processName: String, bundleID: String? = nil) -> Entry? {
        if let hit = entries[processName] { return hit }
        if let bundleID, let hit = entries[bundleID] { return hit }
        if let last = bundleID?.split(separator: ".").last.map(String.init),
           let hit = entries[last] { return hit }
        return nil
    }

    /// Numele afișat oriunde în interfață: traducerea dacă există, altfel
    /// numele aplicației din Finder, altfel numele brut al procesului.
    func friendlyName(processName: String, bundleID: String?, displayName: String?) -> String {
        lookup(processName: processName, bundleID: bundleID)?.name
            ?? displayName
            ?? processName
    }

    func detail(processName: String, bundleID: String?) -> String? {
        lookup(processName: processName, bundleID: bundleID)?.detail
    }
}
