import AppKit
import Foundation

/// Dezinstalarea completă din aplicație (Regula 46), adaptată firewall-ului.
///
/// Extensia de rețea poate fi dezactivată DOAR de aplicația care o conține
/// (cu SIP activ). Asta face deja `UninstallMode` (`--uninstall-extension`),
/// scris pentru Terminal: tipărește și iese cu `exit`. Aici nu e apelat direct —
/// e pornit ca proces-copil al aceluiași executabil, iar codul lui de ieșire
/// (0 / 2 / 1) e tradus în rezultat. Un eșec la extensie OPREȘTE totul:
/// datele și aplicația rămân, ca utilizatorul să poată reîncerca.
@MainActor
final class SelfUninstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case deactivatingExtension
        case removingData
        case movingToTrash
        case finished(needsReboot: Bool)
        case finishedWithLeftovers(needsReboot: Bool, leftovers: [String])
        case failed(String)
    }

    /// Rezultatul pasului de extensie, din codul de ieșire al `UninstallMode`.
    enum ExtensionOutcome: Equatable {
        case removed
        case removedAfterReboot
        case failed

        init(exitCode: Int32) {
            switch exitCode {
            case 0: self = .removed
            case 2: self = .removedAfterReboot
            default: self = .failed
            }
        }
    }

    /// Pașii cu efect real — înlocuiți în teste, ca logica să fie verificată
    /// fără să atingă extensia, fișierele sau aplicația de pe Mac.
    struct Steps {
        var deactivateExtension: () async -> Int32
        var removeItem: (URL) throws -> Void
        var itemExists: (URL) -> Bool
        var moveAppToTrash: () async throws -> Void
        var clearPreferences: () -> Void
        var terminate: (_ needsReboot: Bool, _ leftovers: [String]) -> Void
    }

    @Published private(set) var phase: Phase = .idle
    private let log = DiagnosticLog("uninstall")

    // MARK: - Ce se șterge

    nonisolated static func userDataPaths(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              bundleID: String = Bundle.main.bundleIdentifier ?? "dev.gordas.GDCFirewall") -> [URL] {
        let library = home.appendingPathComponent("Library")
        return [
            "Application Support/GDCFirewall",
            "Caches/\(bundleID)",
            "HTTPStorages/\(bundleID)",
            "HTTPStorages/\(bundleID).binarycookies",
            "WebKit/\(bundleID)",
            "Saved Application State/\(bundleID).savedState",
            "Logs/GDCFirewall",
            "Logs/GDCFirewall.log",
            "Logs/GDCFirewall.log.1",
            "Logs/GDCFirewall-cleanup.log",
            "Preferences/\(bundleID).plist",
        ].map { library.appendingPathComponent($0) }
    }

    /// Ce rămâne: regulile scrise de motor, într-un folder deținut de sistem
    /// (root). Ștergerea lui ar cere parola de administrator pentru un câștig
    /// de câțiva kiloocteți; rămâne pentru o eventuală reinstalare.
    nonisolated static let keptSystemPath = "/Library/Application Support/GDC Firewall"

    // MARK: - Execuția

    func run(steps: Steps) async {
        guard phase == .idle || isFailed else { return }
        phase = .deactivatingExtension
        log.info("Dezinstalare pornită din aplicație")
        let outcome = ExtensionOutcome(exitCode: await steps.deactivateExtension())
        guard outcome != .failed else {
            log.error("Dezinstalare oprită: extensia nu a putut fi dezactivată")
            phase = .failed(L("Extensia de rețea nu a putut fi dezactivată. Nimic altceva nu a fost șters; poți încerca din nou."))
            return
        }

        phase = .removingData
        steps.clearPreferences()
        var leftovers: [String] = []
        for url in Self.userDataPaths() where steps.itemExists(url) {
            do { try steps.removeItem(url) } catch { leftovers.append(url.path) }
        }
        if !leftovers.isEmpty { log.warning("Nu s-au putut șterge: \(leftovers.joined(separator: ", "))") }

        phase = .movingToTrash
        do {
            try await steps.moveAppToTrash()
        } catch {
            log.error("Aplicația nu a putut fi mutată la Coș: \(error.localizedDescription)")
            phase = .failed(L("Extensia și datele au fost eliminate, dar aplicația nu a putut fi mutată la Coș. Mut-o manual din dosarul Aplicații."))
            return
        }
        let needsReboot = outcome == .removedAfterReboot
        if leftovers.isEmpty {
            phase = .finished(needsReboot: needsReboot)
            log.info("Dezinstalare încheiată (repornire necesară: \(needsReboot))")
        } else {
            phase = .finishedWithLeftovers(needsReboot: needsReboot, leftovers: leftovers)
            log.warning("Dezinstalare încheiată cu \(leftovers.count) elemente rămase")
        }
        DiagnosticLog.flush()
        steps.terminate(needsReboot, leftovers)
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

// MARK: - Pașii reali

extension SelfUninstaller.Steps {
    @MainActor
    static var live: Self {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.gordas.GDCFirewall"
        return Self(
            deactivateExtension: {
                await withCheckedContinuation { continuation in
                    guard let executable = Bundle.main.executableURL else { return continuation.resume(returning: 1) }
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = [UninstallMode.flag]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                    do { try process.run() } catch { continuation.resume(returning: 1) }
                }
            },
            removeItem: { try FileManager.default.removeItem(at: $0) },
            itemExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveAppToTrash: {
                try await NSWorkspace.shared.recycle([Bundle.main.bundleURL])
            },
            clearPreferences: {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            },
            terminate: { needsReboot, leftovers in
                if needsReboot || !leftovers.isEmpty {
                    let alert = NSAlert()
                    if leftovers.isEmpty {
                        alert.messageText = L("Repornește Mac-ul")
                        alert.informativeText = L("GDC Firewall a fost dezinstalat. macOS elimină definitiv extensia de rețea la următoarea repornire.")
                    } else {
                        alert.messageText = L("Dezinstalarea s-a încheiat cu elemente rămase")
                        let visible = leftovers.map {
                            $0.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                        }.joined(separator: "\n")
                        let reboot = needsReboot ? "\n\n" + L("Repornește Mac-ul pentru ca macOS să elimine definitiv extensia de rețea.") : ""
                        alert.informativeText = L("Aplicația a fost mutată la Coș, dar aceste elemente nu au putut fi eliminate:\n%@", visible) + reboot
                    }
                    alert.runModal()
                }
                // cfprefsd poate rescrie preferințele la ieșire: se șterg încă o
                // dată, după 2 s, dintr-un proces detașat (Regula 46).
                let plist = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/\(bundleID).plist").path
                let cleanup = Process()
                cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
                cleanup.arguments = ["-c", "sleep 2; rm -f \"$0\"", plist]
                try? cleanup.run()
                NSApp.terminate(nil)
            })
    }
}
