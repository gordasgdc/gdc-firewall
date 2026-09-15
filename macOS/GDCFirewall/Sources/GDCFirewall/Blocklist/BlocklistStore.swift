import Foundation
import Combine
import os.log

/// Filtrarea de domenii, ținută LOCAL și în memorie.
///
/// Decizii de performanță, toate din același motiv — o căutare pe listă
/// stă pe drumul critic al fiecărei conexiuni, deci trebuie să fie O(1) și
/// să nu atingă discul:
///  - lista parsată ajunge într-un `Set<Int>` de hash-uri FNV-1a pe 64 de
///    biți, nu într-un `Set<String>`: ~200 000 de domenii ocupă ~1,6 MB în
///    loc de ~20 MB, iar comparația devine un întreg, nu un string;
///  - căutarea urcă pe etichete („a.b.example.com” → „b.example.com” →
///    „example.com”), maximum câțiva pași, ca subdomeniile să fie prinse
///    fără să ținem fiecare subdomeniu separat în listă;
///  - descărcarea și parsarea rulează pe o coadă de fundal; UI-ul citește
///    doar `@Published`-urile de stare.
///
/// Coliziunile de hash sunt teoretic posibile (un domeniu nevinovat blocat
/// din greșeală). Probabilitatea la 200 000 de intrări pe 64 de biți e sub
/// 10^-9, iar `allowList` dă utilizatorului o portiță imediată — de aia e
/// un compromis acceptabil, nu o scăpare.
final class BlocklistStore: ObservableObject {
    static let shared = BlocklistStore()

    private static let enabledKey = "GDCFirewall.blocklist.enabledLevels"
    private static let updatedKey = "GDCFirewall.blocklist.lastUpdated"
    private static let allowKey = "GDCFirewall.blocklist.allowList"

    private let log = Logger(subsystem: "dev.gordas.GDCFirewall", category: "blocklist")
    private let queue = DispatchQueue(label: "dev.gordas.GDCFirewall.blocklist", qos: .utility)

    /// Comutator independent per nivel (cerut explicit), dar aplicat
    /// cumulativ: se descarcă lista celui mai înalt nivel bifat.
    @Published private(set) var enabledLevels: Set<BlocklistLevel>
    @Published private(set) var domainCount: Int = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isUpdating = false
    @Published private(set) var lastError: String?

    /// Domenii pe care utilizatorul le-a deblocat manual. Bat întotdeauna
    /// lista — nicio listă publică nu are ultimul cuvânt pe Mac-ul lui.
    @Published private(set) var allowList: Set<String>

    private var hashes: Set<UInt64> = []

    private var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GDCFirewall", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("blocklist.cache")
    }

    private init() {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: Self.enabledKey)
        // Prima pornire: nivelul Minim e activ, restul nu. Un firewall
        // pentru neinițiați care pornește cu blocarea pornografiei activată
        // implicit ar fi o decizie luată în locul utilizatorului.
        enabledLevels = Set((saved ?? [BlocklistLevel.minim.rawValue]).compactMap(BlocklistLevel.init(rawValue:)))
        lastUpdated = defaults.object(forKey: Self.updatedKey) as? Date
        allowList = Set(defaults.stringArray(forKey: Self.allowKey) ?? [])
        loadCache()
    }

    // MARK: - Interogare (drumul critic)

    /// `true` = domeniul e pe listă și trebuie blocat.
    /// Se apelează pentru fiecare conexiune, deci nu alocă nimic inutil.
    func isBlocked(_ host: String) -> Bool {
        guard !hashes.isEmpty else { return false }
        let host = Self.normalize(host)
        guard !allowList.contains(host) else { return false }

        var slice = Substring(host)
        while true {
            if allowList.contains(String(slice)) { return false }
            if hashes.contains(Self.fnv1a(slice)) { return true }
            guard let dot = slice.firstIndex(of: ".") else { return false }
            slice = slice[slice.index(after: dot)...]
            // Ne oprim la eticheta de vârf: „com” singur nu se blochează.
            if !slice.contains(".") { return false }
        }
    }

    // MARK: - Nivele

    func setLevel(_ level: BlocklistLevel, enabled: Bool) {
        if enabled { enabledLevels.insert(level) } else { enabledLevels.remove(level) }
        UserDefaults.standard.set(enabledLevels.map(\.rawValue), forKey: Self.enabledKey)
        refresh()
    }

    func allow(_ host: String) {
        allowList.insert(Self.normalize(host))
        UserDefaults.standard.set(Array(allowList), forKey: Self.allowKey)
    }

    func removeFromAllowList(_ host: String) {
        allowList.remove(host)
        UserDefaults.standard.set(Array(allowList), forKey: Self.allowKey)
    }

    // MARK: - Actualizare

    /// Butonul „Actualizează listele”, dar și apelul automat la pornire.
    func refresh() {
        guard let top = enabledLevels.max(by: { $0.rank < $1.rank }) else {
            hashes = []
            domainCount = 0
            try? FileManager.default.removeItem(at: cacheURL)
            return
        }
        guard !isUpdating else { return }
        isUpdating = true
        lastError = nil

        var request = URLRequest(url: top.sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.finish(error: error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.finish(error: "Serverul a răspuns cu status \(http.statusCode).")
                return
            }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                self.finish(error: "Lista descărcată nu a putut fi citită.")
                return
            }
            self.queue.async {
                let parsed = Self.parse(text)
                // Lista veche rămâne activă până când cea nouă e gata:
                // niciun interval în care filtrarea e oprită.
                DispatchQueue.main.async {
                    self.hashes = parsed
                    self.domainCount = parsed.count
                    self.lastUpdated = Date()
                    UserDefaults.standard.set(self.lastUpdated, forKey: Self.updatedKey)
                    self.isUpdating = false
                }
                self.writeCache(parsed)
            }
        }.resume()
    }

    private func finish(error: String) {
        DispatchQueue.main.async {
            self.lastError = error
            self.isUpdating = false
            self.log.error("Actualizare blocklist eșuată: \(error, privacy: .public)")
        }
    }

    // MARK: - Parsare

    /// Format hosts: „0.0.0.0 domeniu” sau „127.0.0.1 domeniu”, comentarii
    /// cu `#`. Ignorăm `localhost` și intrările de buclă locală — altfel
    /// blocăm Mac-ul de el însuși.
    static func parse(_ text: String) -> Set<UInt64> {
        var result = Set<UInt64>()
        result.reserveCapacity(250_000)

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.prefix { $0 != "#" }
            guard !line.isEmpty else { continue }
            var fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            let ip = fields.removeFirst()
            guard ip == "0.0.0.0" || ip == "127.0.0.1" || ip == "::1" else { continue }
            for field in fields {
                let host = field.lowercased()
                guard host.contains("."), host != "localhost", !host.hasPrefix("local") else { continue }
                result.insert(fnv1a(Substring(host)))
            }
        }
        return result
    }

    static func normalize(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// FNV-1a pe 64 de biți. Ales fiindcă e câteva linii, fără dependințe,
    /// și rulează pe `Substring` fără să aloce un `String` nou la fiecare
    /// pas de urcare pe etichete.
    static func fnv1a(_ s: Substring) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - Cache pe disc

    /// Cache binar simplu (hash-uri brute), ca pornirea aplicației să nu
    /// depindă de internet și să nu reparseze 200 000 de linii de fiecare dată.
    private func writeCache(_ set: Set<UInt64>) {
        var data = Data(capacity: set.count * 8)
        for hash in set {
            withUnsafeBytes(of: hash.littleEndian) { data.append(contentsOf: $0) }
        }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), data.count % 8 == 0 else { return }
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
