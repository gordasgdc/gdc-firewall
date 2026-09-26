import Foundation

/// Exportul pachetului de diagnostic: numai la cererea utilizatorului, numai
/// local (un ZIP într-un loc ales de el), niciodată trimis automat.
enum DiagnosticExporter {
    struct Options {
        var includePersonalPaths = false
        var includeCrashReports = false
    }

    private static let log = DiagnosticLog("diagnostic")

    /// Construiește pachetul și îl arhivează la `destination`. Rulează pe un
    /// fir de fundal: `log show` poate dura câteva secunde.
    static func export(to destination: URL, options: Options, context: [String: String]) async throws -> DiagnosticManifest {
        let started = Date()
        log.info("Export diagnostic început (căi personale: \(options.includePersonalPaths), crash: \(options.includeCrashReports))")
        DiagnosticLog.flush()
        let result = try await Task.detached(priority: .userInitiated) {
            let builder = DiagnosticBundleBuilder(redactor: DiagnosticRedactor(includePersonalPaths: options.includePersonalPaths))
            let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime])
                .replacingOccurrences(of: ":", with: "")
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("GDCFirewall-Diagnostic-\(stamp)")
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            let manifest = try builder.build(sources: sources(options: options, context: context),
                                             into: folder, manifest: baseManifest(options: options))
            try replaceArchiveAtomically(at: destination) { temporary in
                try zip(folder, to: temporary)
            }
            return manifest
        }.value
        log.info("Export diagnostic reușit în \(String(format: "%.1f", Date().timeIntervalSince(started))) s: "
                 + "\(result.files.count) fișiere, \(result.skipped.count) surse omise")
        return result
    }

    static func baseManifest(options: Options) -> DiagnosticManifest {
        let info = Bundle.main.infoDictionary
        return DiagnosticManifest(
            product: "GDC Firewall",
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            appBuild: info?["CFBundleVersion"] as? String ?? "?",
            engineVersion: LuLu.engineVersion,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            sessionID: DiagnosticLog.sessionID,
            createdAt: ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]),
            personalPathsIncluded: options.includePersonalPaths,
            files: [], skipped: [])
    }

    /// Sursele pachetului. Setările incluse sunt doar cele tehnice, fără date
    /// personale; `context` vine din interfață (starea extensiei, a filtrului).
    static func sources(options: Options, context: [String: String]) -> [DiagnosticSource] {
        var list: [DiagnosticSource] = [
            DiagnosticSource(fileName: "setari.txt") {
                context.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n") + "\n"
            },
            fileSource(DiagnosticLog.fileURL, as: "GDCFirewall.log"),
            fileSource(DiagnosticLog.fileURL.appendingPathExtension("1"), as: "GDCFirewall.log.1"),
            DiagnosticSource(fileName: "unified-aplicatie.log") {
                try unifiedLog(predicate: "subsystem == \"\(DiagnosticLog.subsystem)\"")
            },
            DiagnosticSource(fileName: "unified-motor.log") {
                try unifiedLog(predicate: "subsystem == \"com.objective-see.lulu\"")
            },
        ]
        if options.includeCrashReports {
            list += crashReports().map { fileSource($0, as: "crash-" + $0.lastPathComponent) }
        }
        return list
    }

    static func fileSource(_ url: URL, as name: String) -> DiagnosticSource {
        DiagnosticSource(fileName: name) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DiagnosticExportError.unreadable(L("Fișierul nu există."))
            }
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw DiagnosticExportError.unreadable(L("Fișierul nu a putut fi citit: %@", error.localizedDescription))
            }
        }
    }

    /// Ultimele 5 rapoarte de crash ale aplicației (doar cu acordul explicit).
    static func crashReports() -> [URL] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items
            .filter { $0.lastPathComponent.hasPrefix("GDC Firewall") }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            .prefix(5).map { $0 }
    }

    /// Ultima oră din unified log, pentru un subsistem. Cu limită de timp:
    /// un `log show` blocat nu trebuie să blocheze exportul.
    static func unifiedLog(predicate: String) throws -> String {
        let (status, output) = run("/usr/bin/log", ["show", "--last", "1h", "--style", "compact", "--info", "--predicate", predicate], timeout: 30)
        guard status == 0 else {
            throw DiagnosticExportError.unreadable(L("Jurnalul de sistem nu a putut fi citit (cod %d).", Int(status)))
        }
        return output
    }

    static func zip(_ folder: URL, to destination: URL) throws {
        let (status, _) = run("/usr/bin/ditto", ["-c", "-k", "--keepParent", folder.path, destination.path], timeout: 60)
        guard status == 0 else { throw DiagnosticExportError.archiveFailed(status) }
    }

    /// Creează arhiva lângă destinație și o înlocuiește numai după ce există
    /// un fișier nou, nevid. Un export eșuat nu distruge arhiva precedentă.
    static func replaceArchiveAtomically(at destination: URL,
                                         create: (URL) throws -> Void) throws {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }

        try create(temporary)
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard manager.fileExists(atPath: temporary.path), size > 0 else {
            throw DiagnosticExportError.invalidArchive
        }

        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary,
                                          backupItemName: nil, options: [])
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }

    private static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        // Citire în bucăți, păstrând doar ultimii 4 MB: o oră de log poate fi
        // mare, iar pachetul oricum păstrează doar finalul (Regula 21).
        let keep = 4 * 1024 * 1024
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > keep * 2 { data = data.suffix(keep) }
        }
        process.waitUntilExit()
        timer.cancel()
        return (process.terminationStatus, String(decoding: data.suffix(keep), as: UTF8.self))
    }
}
