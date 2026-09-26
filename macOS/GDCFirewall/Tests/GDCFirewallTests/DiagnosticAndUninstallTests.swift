import XCTest
@testable import GDCFirewall

final class DiagnosticRedactorTests: XCTestCase {
    private let redactor = DiagnosticRedactor(homePath: "/Users/maria")

    func testHomeBecomesTildeAndOtherUsersLoseName() {
        let out = redactor.redact("/Users/maria/Library/Logs/x.log și /Users/ion/Desktop/a și /Users/Shared/b")
        XCTAssertEqual(out, "~/Library/Logs/x.log și /Users/<utilizator>/Desktop/a și /Users/Shared/b")
        XCTAssertFalse(out.contains("maria"))
    }

    func testPersonalPathsAnonymizedByDefaultButSystemPathsKept() {
        let out = redactor.redact("proces /Users/maria/Documente/Proiect/tool → /Applications/Zoom.us.app")
        XCTAssertFalse(out.contains("Documente"))
        XCTAssertFalse(out.contains("Proiect"))
        XCTAssertTrue(out.contains("/Applications/Zoom.us.app"))
        XCTAssertTrue(out.contains("~/<"))
    }

    func testPersonalPathsKeptOnlyWhenRequested() {
        let open = DiagnosticRedactor(homePath: "/Users/maria", includePersonalPaths: true)
        XCTAssertEqual(open.redact("/Users/maria/Documente/tool"), "~/Documente/tool")
    }

    func testDeterministic() {
        let line = "/Users/maria/Downloads/tool token=abc"
        XCTAssertEqual(redactor.redact(line), redactor.redact(line))
        XCTAssertEqual(DiagnosticRedactor.shortHash("x"), DiagnosticRedactor.shortHash("x"))
        XCTAssertNotEqual(DiagnosticRedactor.shortHash("x"), DiagnosticRedactor.shortHash("y"))
    }

    func testSecretsAndEmails() {
        let cases = [
            "password=hunter2", "token: \"abc def\"", "api_key=XYZ", "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.x.y",
            "contact maria.popescu@example.com",
            "cheie " + String(repeating: "a1B2", count: 12),
        ]
        let secrets = ["hunter2", "abc def", "XYZ", "eyJhbGciOiJIUzI1NiJ9", "maria.popescu", "a1B2a1B2a1B2"]
        for (input, secret) in zip(cases, secrets) {
            XCTAssertFalse(redactor.redact(input).contains(secret), input)
        }
    }

    /// Ce e util pentru diagnostic rămâne: UUID-uri, versiuni, destinații.
    func testKeepsUsefulContext() {
        let line = "Pornire GDC Firewall 2.3.5 (build 42) · sesiune 1A2B3C4D · 550e8400-e29b-41d4-a716-446655440000 → zoom.us:443"
        XCTAssertEqual(redactor.redact(line), line)
    }
}

final class DiagnosticBundleTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        // Textul notei de trunchiere se verifică în română, oricare ar fi limba sistemului.
        UserDefaults.standard.set("ro", forKey: Lang.preferenceKey)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removeObject(forKey: Lang.preferenceKey)
    }

    private func base() -> DiagnosticManifest {
        DiagnosticManifest(product: "GDC Firewall", appVersion: "2.3.5", appBuild: "1", engineVersion: "4.5.1",
                           macOS: "test", sessionID: "ABCD1234", createdAt: "now",
                           personalPathsIncluded: false, files: [], skipped: [])
    }

    func testManifestListsFilesSkipsUnreadableAndRedacts() throws {
        let builder = DiagnosticBundleBuilder(redactor: DiagnosticRedactor(homePath: "/Users/maria"))
        let manifest = try builder.build(sources: [
            DiagnosticSource(fileName: "a.log") { "linie /Users/maria/Library/x password=secret\n" },
            DiagnosticSource(fileName: "lipsa.log") { throw DiagnosticExportError.unreadable("Fișierul nu există.") },
        ], into: folder, manifest: base())

        XCTAssertEqual(manifest.files.map(\.name), ["a.log"])
        XCTAssertEqual(manifest.skipped, [.init(source: "lipsa.log", reason: "Fișierul nu există.")])
        let written = try String(contentsOf: folder.appendingPathComponent("a.log"))
        XCTAssertFalse(written.contains("maria"))
        XCTAssertFalse(written.contains("secret"))

        let decoded = try JSONDecoder().decode(DiagnosticManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.appVersion, "2.3.5")
        XCTAssertEqual(decoded.engineVersion, "4.5.1")
        XCTAssertEqual(decoded.sessionID, "ABCD1234")
    }

    func testSkippedReasonIsRedactedBeforeManifestIsWritten() throws {
        let builder = DiagnosticBundleBuilder(redactor: DiagnosticRedactor(homePath: "/Users/maria"))
        let privateReason = "/Users/maria/Documente/secret contact maria@example.com token=secret"
        let manifest = try builder.build(sources: [
            DiagnosticSource(fileName: "privat.log") { throw DiagnosticExportError.unreadable(privateReason) },
        ], into: folder, manifest: base())

        let reason = try XCTUnwrap(manifest.skipped.first?.reason)
        XCTAssertFalse(reason.contains("/Users/maria"))
        XCTAssertFalse(reason.contains("maria@example.com"))
        XCTAssertFalse(reason.contains("token=secret"))
        let written = try String(contentsOf: folder.appendingPathComponent("manifest.json"))
        XCTAssertFalse(written.contains("maria@example.com"))
        XCTAssertFalse(written.contains("token=secret"))
    }

    func testPerFileAndTotalLimits() throws {
        var builder = DiagnosticBundleBuilder(redactor: DiagnosticRedactor(homePath: "/Users/maria"))
        builder.maxBytesPerFile = 1000
        builder.maxTotalBytes = 1500
        let big = (1...200).map { "rând \($0)" }.joined(separator: "\n")
        let manifest = try builder.build(sources: [
            DiagnosticSource(fileName: "1.log") { big },
            DiagnosticSource(fileName: "2.log") { big },
            DiagnosticSource(fileName: "3.log") { big },
        ], into: folder, manifest: base())

        XCTAssertEqual(manifest.files.map(\.truncated), [true, true])
        XCTAssertTrue(manifest.files.allSatisfy { $0.bytes <= 1000 })
        XCTAssertLessThanOrEqual(manifest.files.map(\.bytes).reduce(0, +), 1500)
        XCTAssertEqual(manifest.skipped.map(\.source), ["3.log"])
        let first = try String(contentsOf: folder.appendingPathComponent("1.log"))
        XCTAssertLessThanOrEqual(Data(first.utf8).count, 1000)
        XCTAssertTrue(first.hasPrefix("[… trunchiat:"))
        XCTAssertTrue(first.hasSuffix("rând 200"), "se păstrează cele mai noi rânduri")
    }

    /// Fără loc nici pentru nota de trunchiere, sursa e omisă cu motiv, nu scrisă ciuntită.
    func testSourceSkippedWhenBudgetCannotHoldNotice() throws {
        var builder = DiagnosticBundleBuilder(redactor: DiagnosticRedactor(homePath: "/Users/maria"))
        builder.maxTotalBytes = 1000
        let manifest = try builder.build(sources: [
            DiagnosticSource(fileName: "1.log") { String(repeating: "ab ", count: 330) },  // 990 B, fără aspect de secret
            DiagnosticSource(fileName: "2.log") { String(repeating: "rând\n", count: 50) },
        ], into: folder, manifest: base())
        XCTAssertEqual(manifest.files.map(\.name), ["1.log"])
        XCTAssertEqual(manifest.skipped.map(\.source), ["2.log"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("2.log").path))
    }

    func testTailCutsAtLineBoundary() {
        let (text, truncated) = DiagnosticBundleBuilder.tail(String(repeating: "aaa\n", count: 40) + "bbb\nccc", maxBytes: DiagnosticBundleBuilder.truncationNoticeBytes + 6)
        XCTAssertTrue(truncated)
        XCTAssertTrue(text.hasSuffix("\nccc"))
        XCTAssertEqual(DiagnosticBundleBuilder.tail("scurt", maxBytes: 100).1, false)
    }

    func testTailNeverExceedsEvenATinyBudget() {
        for budget in 0...80 {
            let (text, truncated) = DiagnosticBundleBuilder.tail(String(repeating: "ț", count: 200), maxBytes: budget)
            XCTAssertTrue(truncated)
            XCTAssertLessThanOrEqual(Data(text.utf8).count, budget)
        }
    }

    func testMissingFileSourceThrowsReadableReason() {
        let source = DiagnosticExporter.fileSource(URL(fileURLWithPath: "/nonexistent/\(UUID())"), as: "x.log")
        XCTAssertThrowsError(try source.load())
    }
}

final class DiagnosticArchiveReplacementTests: XCTestCase {
    private var folder: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("diag-atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        destination = folder.appendingPathComponent("diagnostic.zip")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testSuccessfulArchiveAtomicallyReplacesExistingDestination() throws {
        try Data("vechi".utf8).write(to: destination)
        try DiagnosticExporter.replaceArchiveAtomically(at: destination) { temporary in
            try Data("nou-valid".utf8).write(to: temporary)
        }
        XCTAssertEqual(try String(contentsOf: destination), "nou-valid")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["diagnostic.zip"])
    }

    func testFailedArchiveKeepsExistingDestinationAndRemovesTemporary() throws {
        enum Simulated: Error { case failed }
        try Data("vechi-intact".utf8).write(to: destination)
        XCTAssertThrowsError(try DiagnosticExporter.replaceArchiveAtomically(at: destination) { temporary in
            try Data("partial".utf8).write(to: temporary)
            throw Simulated.failed
        })
        XCTAssertEqual(try String(contentsOf: destination), "vechi-intact")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["diagnostic.zip"])
    }
}

@MainActor
final class UninstallModeTests: XCTestCase {
    private enum Simulated: LocalizedError {
        case load, remove
        var errorDescription: String? {
            switch self {
            case .load: return "load failed"
            case .remove: return "remove failed"
            }
        }
    }

    func testLoadErrorStopsBeforeExtensionDeactivation() async {
        var deactivated = false
        let code = await UninstallMode.perform(steps: .init(
            loadFilterConfiguration: { throw Simulated.load },
            removeFilterConfiguration: {},
            deactivateExtension: { deactivated = true; return .removed }))
        XCTAssertEqual(code, 1)
        XCTAssertFalse(deactivated)
    }

    func testRemoveErrorStopsBeforeExtensionDeactivation() async {
        var deactivated = false
        let code = await UninstallMode.perform(steps: .init(
            loadFilterConfiguration: { true },
            removeFilterConfiguration: { throw Simulated.remove },
            deactivateExtension: { deactivated = true; return .removed }))
        XCTAssertEqual(code, 1)
        XCTAssertFalse(deactivated)
    }

    func testExtensionRemovalAfterRebootReturnsTwo() async {
        let code = await UninstallMode.perform(steps: .init(
            loadFilterConfiguration: { false },
            removeFilterConfiguration: {},
            deactivateExtension: { .removedAfterReboot }))
        XCTAssertEqual(code, 2)
    }
}

@MainActor
final class SelfUninstallerTests: XCTestCase {
    private var removed: [URL] = []
    private var trashed = false
    private var terminated: Bool?
    private var leftoversReported: [String] = []
    private var prefsCleared = false

    private func steps(exit: Int32, trashFails: Bool = false, existing: Set<String>? = nil,
                       removeFails: Set<String> = []) -> SelfUninstaller.Steps {
        SelfUninstaller.Steps(
            deactivateExtension: { exit },
            removeItem: {
                if removeFails.contains($0.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
                self.removed.append($0)
            },
            itemExists: { existing?.contains($0.lastPathComponent) ?? true },
            moveAppToTrash: {
                if trashFails { throw CocoaError(.fileWriteNoPermission) }
                self.trashed = true
            },
            clearPreferences: { self.prefsCleared = true },
            terminate: {
                self.terminated = $0
                self.leftoversReported = $1
            })
    }

    func testExitCodeMapping() {
        XCTAssertEqual(SelfUninstaller.ExtensionOutcome(exitCode: 0), .removed)
        XCTAssertEqual(SelfUninstaller.ExtensionOutcome(exitCode: 2), .removedAfterReboot)
        XCTAssertEqual(SelfUninstaller.ExtensionOutcome(exitCode: 1), .failed)
        XCTAssertEqual(SelfUninstaller.ExtensionOutcome(exitCode: 15), .failed)
    }

    /// Extensia nu s-a dezactivat → nimic altceva nu se atinge.
    func testExtensionFailureStopsEverything() async {
        let uninstaller = SelfUninstaller()
        await uninstaller.run(steps: steps(exit: 1))
        guard case .failed = uninstaller.phase else { return XCTFail("\(uninstaller.phase)") }
        XCTAssertTrue(removed.isEmpty)
        XCTAssertFalse(prefsCleared)
        XCTAssertFalse(trashed)
        XCTAssertNil(terminated)
    }

    func testSuccessRemovesOnlyExistingDataThenTrashesAndQuits() async {
        let uninstaller = SelfUninstaller()
        await uninstaller.run(steps: steps(exit: 0, existing: ["GDCFirewall.log", "GDCFirewall"]))
        XCTAssertEqual(uninstaller.phase, .finished(needsReboot: false))
        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), ["GDCFirewall.log", "GDCFirewall"])
        XCTAssertTrue(prefsCleared)
        XCTAssertTrue(trashed)
        XCTAssertEqual(terminated, false)
    }

    func testRebootNeededIsReported() async {
        let uninstaller = SelfUninstaller()
        await uninstaller.run(steps: steps(exit: 2))
        XCTAssertEqual(uninstaller.phase, .finished(needsReboot: true))
        XCTAssertEqual(terminated, true)
    }

    func testTrashFailureKeepsAppRunningWithMessage() async {
        let uninstaller = SelfUninstaller()
        await uninstaller.run(steps: steps(exit: 0, trashFails: true))
        guard case .failed = uninstaller.phase else { return XCTFail("\(uninstaller.phase)") }
        XCTAssertNil(terminated)
    }

    func testPartialCleanupIsReportedAndNotMarkedFullyFinished() async {
        let uninstaller = SelfUninstaller()
        await uninstaller.run(steps: steps(exit: 0, existing: ["GDCFirewall.log"], removeFails: ["GDCFirewall.log"]))
        guard case .finishedWithLeftovers(let needsReboot, let leftovers) = uninstaller.phase else {
            return XCTFail("\(uninstaller.phase)")
        }
        XCTAssertFalse(needsReboot)
        XCTAssertEqual(leftovers.map { URL(fileURLWithPath: $0).lastPathComponent }, ["GDCFirewall.log"])
        XCTAssertEqual(leftoversReported, leftovers)
        XCTAssertTrue(trashed)
        XCTAssertEqual(terminated, false)
    }

    func testDataPathsStayInsideUserLibraryAndKeepRules() {
        let home = URL(fileURLWithPath: "/Users/test")
        let paths = SelfUninstaller.userDataPaths(home: home, bundleID: "dev.gordas.GDCFirewall")
        XCTAssertTrue(paths.allSatisfy { $0.path.hasPrefix("/Users/test/Library/") })
        XCTAssertTrue(paths.contains { $0.path.hasSuffix("Logs/GDCFirewall.log") })
        XCTAssertTrue(paths.contains { $0.path.hasSuffix("Preferences/dev.gordas.GDCFirewall.plist") })
        XCTAssertFalse(paths.contains { $0.path.contains(SelfUninstaller.keptSystemPath) })
    }
}

/// Exportul real, cap-coadă: surse reale (log de test, `log show`), ZIP cu `ditto`.
final class DiagnosticExportIntegrationTests: XCTestCase {
    func testLiveExportCreatesZipWithManifest() async throws {
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        DiagnosticLog("test").info("linie de test pentru export")
        let manifest = try await DiagnosticExporter.export(to: zip, options: .init(), context: ["stare": "test"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertEqual(manifest.sessionID, DiagnosticLog.sessionID)
        XCTAssertTrue(manifest.files.map(\.name).contains("setari.txt"))
        XCTAssertEqual(Set(manifest.files.map(\.name) + manifest.skipped.map(\.source)).count, 5, "fiecare sursă e fie inclusă, fie omisă cu motiv")

        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        list.arguments = ["-1", zip.path]
        let pipe = Pipe()
        list.standardOutput = pipe
        try list.run()
        list.waitUntilExit()
        let entries = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(entries.contains("manifest.json"))
        XCTAssertTrue(entries.contains("setari.txt"))
    }
}
