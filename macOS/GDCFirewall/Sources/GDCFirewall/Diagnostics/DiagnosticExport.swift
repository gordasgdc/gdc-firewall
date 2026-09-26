import Foundation
import CryptoKit

// MARK: - Redactare

/// Curăță textul unui pachet de diagnostic înainte să părăsească aplicația.
/// Deterministă: aceeași intrare dă mereu aceeași ieșire (numele ascunse devin
/// un cod scurt stabil, ca două linii despre același fișier să rămână
/// corelabile fără ca numele să apară).
///
/// Ce se elimină întotdeauna: numele contului (dosarul personal devine `~`),
/// adresele de e-mail, valorile de tip parolă/token/cheie și șirurile lungi
/// care arată a secret. Căile din dosarul personal (în afara `~/Library`) se
/// anonimizează, cu excepția cazului în care utilizatorul cere explicit
/// includerea lor.
struct DiagnosticRedactor {
    let homePath: String
    let includePersonalPaths: Bool

    init(homePath: String = FileManager.default.homeDirectoryForCurrentUser.path,
         includePersonalPaths: Bool = false) {
        self.homePath = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        self.includePersonalPaths = includePersonalPaths
    }

    private static let rules: [(NSRegularExpression, String)] = [
        // întâi tokenul „Bearer”, altfel regula cheie=valoare ar ascunde doar cuvântul „Bearer”
        (try! NSRegularExpression(pattern: #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#), "Bearer <redactat>"),
        // cheie=valoare / cheie: valoare pentru secrete
        (try! NSRegularExpression(pattern: #"(?i)\b(password|passwd|pwd|parola|token|secret|api[_-]?key|access[_-]?key|authorization|cookie|licen[sț]e?[_-]?(?:key|code|cod)?)(\s*[:=]\s*)("[^"]*"|\S+)"#),
         "$1$2<redactat>"),
        (try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#), "<email>"),
        // șiruri lungi hex/base64 fără spații: chei, tokenuri, cookie-uri
        (try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9+=_-])[A-Za-z0-9+=_-]{40,}(?![A-Za-z0-9+=_-])"#), "<valoare-lungă>"),
    ]

    func redact(_ text: String) -> String {
        var result = text
        // Căile din alte conturi (/Users/<altcineva>/…) își pierd numele.
        result = replace(#"/Users/(?!Shared/)[^/\s"']+"#, in: result) { match in
            match == homePath ? "~" : "/Users/<utilizator>"
        }
        result = result.replacingOccurrences(of: homePath, with: "~")
        if !includePersonalPaths {
            result = replace(#"~/(?!Library/)[^\s"'·,;)]+"#, in: result) { anonymizedPersonalPath($0) }
        }
        for (regex, template) in Self.rules {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }

    /// `~/Documente/Proiect secret/tool` → `~/<a1b2c3>/<d4e5f6>/<0718aa>`.
    private func anonymizedPersonalPath(_ path: String) -> String {
        let parts = path.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false)
        return "~/" + parts.map { "<\(Self.shortHash(String($0)))>" }.joined(separator: "/")
    }

    static func shortHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    private func replace(_ pattern: String, in text: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var output = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            output += text[last..<range.lowerBound]
            output += transform(String(text[range]))
            last = range.upperBound
        }
        output += text[last...]
        return output
    }
}

// MARK: - Manifest

struct DiagnosticManifest: Codable, Equatable {
    struct File: Codable, Equatable {
        let name: String
        let bytes: Int
        /// Sursa depășea limita: s-au păstrat doar ultimele rânduri.
        let truncated: Bool
    }

    struct Skipped: Codable, Equatable {
        let source: String
        let reason: String
    }

    let product: String
    let appVersion: String
    let appBuild: String
    let engineVersion: String
    let macOS: String
    let sessionID: String
    let createdAt: String
    let personalPathsIncluded: Bool
    var files: [File]
    var skipped: [Skipped]
}

// MARK: - Pachetul

/// O sursă de text pentru pachet. `load` poate arunca — sursa apare atunci în
/// `skipped`, cu motivul, iar exportul continuă cu restul.
struct DiagnosticSource {
    let fileName: String
    let load: () throws -> String
}

enum DiagnosticExportError: LocalizedError {
    case unreadable(String)
    case archiveFailed(Int32)
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return reason
        case .archiveFailed(let status): return L("Arhiva nu a putut fi creată (cod %d).", Int(status))
        case .invalidArchive: return L("Arhiva creată este goală sau lipsește.")
        }
    }
}

struct DiagnosticBundleBuilder {
    /// Limită per fișier și totală — pachetul trebuie să poată fi trimis pe e-mail.
    var maxBytesPerFile = 2 * 1024 * 1024
    var maxTotalBytes = 8 * 1024 * 1024
    let redactor: DiagnosticRedactor

    /// Scrie sursele redactate + `manifest.json` în `folder` și întoarce manifestul.
    func build(sources: [DiagnosticSource], into folder: URL, manifest base: DiagnosticManifest) throws -> DiagnosticManifest {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest = base
        manifest.files = []
        manifest.skipped = []
        var total = 0
        for source in sources {
            let raw: String
            do {
                raw = try source.load()
            } catch {
                manifest.skipped.append(.init(source: source.fileName, reason: redactor.redact(error.localizedDescription)))
                continue
            }
            let budget = min(maxBytesPerFile, maxTotalBytes - total)
            let redacted = redactor.redact(raw)
            // O sursă care nu încape și pentru care nu mai rămâne loc nici
            // măcar de nota de trunchiere se omite explicit, nu se scrie ciuntită.
            let fits = Data(redacted.utf8).count <= budget
            guard budget > 0, fits || budget > Self.truncationNoticeBytes else {
                manifest.skipped.append(.init(source: source.fileName, reason: L("Limita totală a pachetului a fost atinsă.")))
                continue
            }
            let (text, truncated) = Self.tail(redacted, maxBytes: budget)
            let data = Data(text.utf8)
            try data.write(to: folder.appendingPathComponent(source.fileName))
            total += data.count
            manifest.files.append(.init(name: source.fileName, bytes: data.count, truncated: truncated))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return manifest
    }

    /// Ultimii `maxBytes` octeți, tăiați la început de rând (cele mai noi
    /// evenimente sunt la final și sunt cele care contează).
    static var truncationNoticeBytes: Int { Data(truncationNotice.utf8).count }
    private static var truncationNotice: String { L("[… trunchiat: s-au păstrat doar cele mai recente rânduri]") + "\n" }

    static func tail(_ text: String, maxBytes: Int) -> (String, Bool) {
        let data = Data(text.utf8)
        guard data.count > maxBytes else { return (text, false) }
        guard maxBytes > 0 else { return ("", true) }
        let notice = truncationNotice
        let noticeData = Data(notice.utf8)
        // Limitele normale sunt mult mai mari decât nota. Pentru un buget
        // artificial minuscul păstrăm un prefix UTF-8 valid al notei și nimic
        // din conținut, fără să depășim nici măcar cu un octet limita.
        guard noticeData.count < maxBytes else {
            return (utf8Prefix(notice, maxBytes: maxBytes), true)
        }
        let contentBudget = maxBytes - noticeData.count
        var slice = String(decoding: data.suffix(contentBudget), as: UTF8.self)
        if let newline = slice.firstIndex(of: "\n") { slice = String(slice[slice.index(after: newline)...]) }
        let result = notice + slice
        // `String(decoding:)` poate înlocui o secvență UTF-8 tăiată; această
        // gardă păstrează limita strictă și în acel caz.
        return Data(result.utf8).count <= maxBytes
            ? (result, true)
            : (utf8Prefix(result, maxBytes: maxBytes), true)
    }

    private static func utf8Prefix(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var result = ""
        var used = 0
        for scalar in text.unicodeScalars {
            let part = String(scalar)
            let bytes = part.utf8.count
            guard used + bytes <= maxBytes else { break }
            result.append(contentsOf: part)
            used += bytes
        }
        return result
    }
}
