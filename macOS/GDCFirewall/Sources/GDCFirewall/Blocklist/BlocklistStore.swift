import Foundation
import Combine

/// Niveluri suplimentare StevenBlack peste baza „Unified” (reclame + malware).
/// Fiecare corespunde listei `alternates/<nume>/hosts` din proiectul
/// StevenBlack/hosts, care include deja baza; îmbinarea le reunește.
enum BlocklistTier: String, CaseIterable, Identifiable, Codable {
    case fakenews, gambling, porn, social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fakenews: return L("+Știri false")
        case .gambling: return L("+Jocuri de noroc")
        case .porn: return L("+Pornografie")
        case .social: return L("+Rețele sociale")
        }
    }

    var summary: String {
        switch self {
        case .fakenews: return L("Site-uri cunoscute pentru știri false.")
        case .gambling: return L("Site-uri de pariuri și jocuri de noroc.")
        case .porn: return L("Conținut pentru adulți.")
        case .social: return L("Facebook, Instagram, TikTok, X și alte rețele sociale.")
        }
    }

    var sourceURL: URL {
        URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/\(rawValue)/hosts")!
    }
}

/// O listă adăugată de utilizator („Adaugă blocklist…”): format hosts sau un
/// domeniu pe linie.
struct CustomBlocklist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var isEnabled = true
}

/// Blocklist-ul: surse → o singură listă îmbinată → aplicată de MOTOR.
///
/// De ce în motor: GDC vede doar conexiunile care ajung la o alertă. O
/// aplicație deja permisă (un browser) nu mai trimite alerte, deci domeniile
/// ei nu treceau prin nicio verificare. Motorul LuLu are propriul mecanism
/// (`useBlockList` + `blockList`, Extension/BlockOrAllowList.m), aplicat
/// FIECĂREI conexiuni înaintea regulilor și reîncărcat singur când fișierul
/// se schimbă. GDC doar produce fișierul.
///
/// Motorul verifică blocklist-ul ÎNAINTEA listei lui de excepții, deci
/// excepțiile utilizatorului se scot direct din fișier, la îmbinare.
///
/// Memorie (Regula 21): sursele se parsează linie cu linie, unicitatea se
/// ține ca hash-uri FNV-1a de 64 de biți (~1,6 MB la 200 000 de domenii),
/// iar domeniile se scriu direct în fișier, nu se adună într-o listă.
final class BlocklistStore: ObservableObject {
    static let shared = BlocklistStore()

    private static let enabledKey = "GDCFirewall.blocklist.enabled"
    private static let tiersKey = "GDCFirewall.blocklist.tiers"
    private static let customKey = "GDCFirewall.blocklist.custom"
    private static let updatedKey = "GDCFirewall.blocklist.lastUpdated"
    private static let allowKey = "GDCFirewall.blocklist.allowList"
    private static let legacyLevelsKey = "GDCFirewall.blocklist.enabledLevels"

    static let unifiedURL = URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!

    private let log = DiagnosticLog("blocklist")

    @Published private(set) var isEnabled: Bool
    @Published private(set) var tiers: Set<BlocklistTier>
    @Published private(set) var customLists: [CustomBlocklist]
    @Published private(set) var domainCount = 0
    /// Domenii NOI aduse de fiecare sursă (după eliminarea duplicatelor), în
    /// ordinea îmbinării — baza întâi.
    @Published private(set) var sourceCounts: [(name: String, count: Int)] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isUpdating = false
    @Published private(set) var lastError: String?
    /// Domenii deblocate de utilizator. Nicio listă publică nu are ultimul
    /// cuvânt pe Mac-ul lui.
    @Published private(set) var allowList: Set<String>

    /// Pentru verificări rapide din interfață („e blocat X?”).
    private var hashes: Set<UInt64> = []

    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GDCFirewall", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    /// Fișierul citit de motor: un domeniu pe linie.
    static var mergedFileURL: URL { supportDirectory.appendingPathComponent("blocklist.txt") }
    private static var cacheURL: URL { supportDirectory.appendingPathComponent("blocklist.cache") }

    private init() {
        let defaults = UserDefaults.standard
        if let legacy = defaults.stringArray(forKey: Self.legacyLevelsKey) {
            // v2.2.x: „Minim/Mediu/Maxim”. Mediu descărca de fapt fakenews,
            // Maxim porn+gambling — le traducem exact în nivelurile noi.
            let enabled = !legacy.isEmpty
            var migrated = Set<BlocklistTier>()
            if legacy.contains("mediu") { migrated.insert(.fakenews) }
            if legacy.contains("maxim") { migrated.formUnion([.porn, .gambling]) }
            isEnabled = enabled
            tiers = migrated
            defaults.set(enabled, forKey: Self.enabledKey)
            defaults.set(migrated.map(\.rawValue), forKey: Self.tiersKey)
            defaults.removeObject(forKey: Self.legacyLevelsKey)
        } else {
            // Prima pornire: baza activă, fără niveluri suplimentare — blocarea
            // pornografiei sau a rețelelor sociale e o alegere a utilizatorului.
            isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
            tiers = Set((defaults.stringArray(forKey: Self.tiersKey) ?? []).compactMap(BlocklistTier.init(rawValue:)))
        }
        customLists = (defaults.data(forKey: Self.customKey)).flatMap { try? JSONDecoder().decode([CustomBlocklist].self, from: $0) } ?? []
        lastUpdated = defaults.object(forKey: Self.updatedKey) as? Date
        allowList = Set(defaults.stringArray(forKey: Self.allowKey) ?? [])
        loadCache()
    }

    // MARK: - Interogare

    /// Verificare locală (interfață, alerte). Blocarea efectivă o face motorul.
    func isBlocked(_ host: String) -> Bool {
        guard isEnabled, !hashes.isEmpty else { return false }
        let host = Self.normalize(host)
        guard !allowList.contains(host) else { return false }
        var slice = Substring(host)
        while true {
            if allowList.contains(String(slice)) { return false }
            if hashes.contains(Self.fnv1a(slice)) { return true }
            guard let dot = slice.firstIndex(of: ".") else { return false }
            slice = slice[slice.index(after: dot)...]
            if !slice.contains(".") { return false }
        }
    }

    // MARK: - Configurare

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        log.info("Blocklist \(enabled ? "pornit" : "oprit")")
        if enabled && !FileManager.default.fileExists(atPath: Self.mergedFileURL.path) {
            refresh()
        } else {
            applyToEngine()
        }
    }

    func setTier(_ tier: BlocklistTier, enabled: Bool) {
        if enabled { tiers.insert(tier) } else { tiers.remove(tier) }
        UserDefaults.standard.set(tiers.map(\.rawValue), forKey: Self.tiersKey)
        refresh()
    }

    func addCustomList(name: String, url: String) {
        customLists.append(CustomBlocklist(name: name, url: url))
        saveCustomLists()
        refresh()
    }

    func setCustomList(_ id: UUID, enabled: Bool) {
        guard let index = customLists.firstIndex(where: { $0.id == id }) else { return }
        customLists[index].isEnabled = enabled
        saveCustomLists()
        refresh()
    }

    func removeCustomList(_ id: UUID) {
        customLists.removeAll { $0.id == id }
        saveCustomLists()
        refresh()
    }

    private func saveCustomLists() {
        UserDefaults.standard.set(try? JSONEncoder().encode(customLists), forKey: Self.customKey)
    }

    func allow(_ host: String) {
        allowList.insert(Self.normalize(host))
        UserDefaults.standard.set(Array(allowList), forKey: Self.allowKey)
        refresh()
    }

    func removeFromAllowList(_ host: String) {
        allowList.remove(host)
        UserDefaults.standard.set(Array(allowList), forKey: Self.allowKey)
        refresh()
    }

    // MARK: - Motor

    /// Pornit + fișier existent → motorul blochează din el. Altfel îl oprim
    /// explicit (cheia goală golește lista din memoria motorului).
    func applyToEngine() {
        let active = isEnabled && FileManager.default.fileExists(atPath: Self.mergedFileURL.path)
        DaemonBridge.shared.updatePreferences([
            LuLu.Pref.useBlockList: active,
            LuLu.Pref.blockList: active ? Self.mergedFileURL.path : "",
        ])
    }

    // MARK: - Actualizare și îmbinare

    /// Butonul „Actualizează”, schimbarea nivelurilor și pornirea aplicației.
    func refresh() {
        guard isEnabled else { applyToEngine(); return }
        guard !isUpdating else { return }
        isUpdating = true
        lastError = nil

        var sources: [(name: String, url: URL)] = [(L("Unified (bază)"), Self.unifiedURL)]
        sources += BlocklistTier.allCases.filter(tiers.contains).map { ($0.title, $0.sourceURL) }
        sources += customLists.filter(\.isEnabled).compactMap { list in URL(string: list.url).map { (list.name, $0) } }
        let allSources = sources
        let exceptions = allowList

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let result = try await Self.merge(allSources, excluding: exceptions)
                await MainActor.run {
                    self.hashes = result.hashes
                    self.domainCount = result.hashes.count
                    self.sourceCounts = result.counts
                    self.lastUpdated = Date()
                    self.isUpdating = false
                    UserDefaults.standard.set(self.lastUpdated, forKey: Self.updatedKey)
                    self.log.info("Blocklist îmbinat: \(result.hashes.count) domenii din \(allSources.count) surse ("
                                  + result.counts.map { "\($0.name) +\($0.count)" }.joined(separator: ", ") + ")")
                    self.applyToEngine()
                }
                Self.writeCache(result.hashes)
            } catch {
                // Lista veche rămâne activă: niciun interval fără filtrare.
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isUpdating = false
                    self.log.error("Actualizare blocklist eșuată: \(error.localizedDescription)")
                }
            }
        }
    }

    struct MergeError: LocalizedError {
        let source: String
        let detail: String
        var errorDescription: String? { L("%@: %@", source, detail) }
    }

    /// Descarcă sursele pe rând și le scrie, fără duplicate și fără excepții,
    /// într-un fișier temporar mutat atomic peste cel citit de motor.
    private static func merge(_ sources: [(name: String, url: URL)], excluding exceptions: Set<String>) async throws
        -> (hashes: Set<UInt64>, counts: [(name: String, count: Int)]) {
        let temp = supportDirectory.appendingPathComponent("blocklist.tmp")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: temp) else {
            throw MergeError(source: "blocklist.txt", detail: L("nu pot scrie fișierul"))
        }
        defer { try? out.close() }

        var hashes = Set<UInt64>()
        hashes.reserveCapacity(250_000)
        var counts: [(name: String, count: Int)] = []
        let excluded = Set(exceptions.map { fnv1a(Substring($0)) })

        for source in sources {
            var request = URLRequest(url: source.url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw MergeError(source: source.name, detail: L("Serverul a răspuns cu status %d.", http.statusCode))
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw MergeError(source: source.name, detail: L("Lista descărcată nu a putut fi citită."))
            }
            var added = 0
            var chunk = ""
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let host = domain(in: rawLine) else { continue }
                let hash = fnv1a(Substring(host))
                guard !excluded.contains(hash), hashes.insert(hash).inserted else { continue }
                chunk += host
                chunk += "\n"
                added += 1
                if chunk.utf8.count > 64_000 {
                    try out.write(contentsOf: Data(chunk.utf8))
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty { try out.write(contentsOf: Data(chunk.utf8)) }
            counts.append((source.name, added))
        }
        try out.synchronize()
        if FileManager.default.fileExists(atPath: mergedFileURL.path) {
            _ = try FileManager.default.replaceItemAt(mergedFileURL, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: mergedFileURL)
        }
        return (hashes, counts)
    }

    /// O linie de sursă → domeniu, sau nil. Acceptă formatul hosts
    /// („0.0.0.0 domeniu”) și listele cu un domeniu pe linie. Ignoră
    /// comentariile, `localhost` și intrările locale — altfel Mac-ul s-ar
    /// bloca de el însuși.
    static func domain(in rawLine: Substring) -> String? {
        let line = rawLine.prefix { $0 != "#" }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
        guard let last = fields.last else { return nil }
        if fields.count >= 2 {
            let ip = fields[0]
            guard ip == "0.0.0.0" || ip == "127.0.0.1" || ip == "::1" else { return nil }
        }
        let host = normalize(String(last))
        guard host.contains("."), host != "localhost", !host.hasPrefix("local"),
              host != "0.0.0.0", !host.contains("/") else { return nil }
        return host
    }

    static func normalize(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// FNV-1a pe 64 de biți: câteva linii, fără dependințe, pe `Substring`.
    static func fnv1a(_ s: Substring) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - Cache pe disc

    /// Hash-urile brute, ca pornirea să nu depindă de internet.
    private static func writeCache(_ set: Set<UInt64>) {
        var data = Data(capacity: set.count * 8)
        for hash in set {
            withUnsafeBytes(of: hash.littleEndian) { data.append(contentsOf: $0) }
        }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL), data.count % 8 == 0 else { return }
        var set = Set<UInt64>()
        set.reserveCapacity(data.count / 8)
        data.withUnsafeBytes { raw in
            for i in stride(from: 0, to: raw.count, by: 8) {
                set.insert(UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: UInt64.self)))
            }
        }
        hashes = set
        domainCount = set.count
    }
}
