import AppKit
import NetworkExtension
import SystemExtensions

/// `GDC Firewall --uninstall-extension` — apelat de Dezinstalare_GDCFirewall.command.
/// Fără SIP dezactivat, extensia de rețea poate fi dezactivată DOAR de aplicația
/// care o conține; tot aplicația scoate configurația de filtru din Setări →
/// Rețea → Filtre. Rulează fără interfață și scrie în Terminal.
/// Cod de ieșire: 0 = dezactivată sau inexistentă, 2 = se finalizează la
/// repornire, 1 = eșec.
enum UninstallMode {
    static let flag = "--uninstall-extension"
    static var isRequested: Bool { CommandLine.arguments.contains(flag) }
    private static let log = DiagnosticLog("uninstall")

    enum DeactivationOutcome: Equatable {
        case removed
        case removedAfterReboot
        case notInstalled
        case failed(String)
    }

    /// Pașii sunt injectabili ca fluxul fail-safe să poată fi verificat fără
    /// să atingă filtrul sau extensia instalată pe Mac.
    struct Steps {
        var loadFilterConfiguration: () async throws -> Bool
        var removeFilterConfiguration: () async throws -> Void
        var deactivateExtension: () async -> DeactivationOutcome
    }

    private static var activeDelegate: Delegate?

    @MainActor
    static func run() {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { say("  ✗ timp depășit"); exit(1) }
        Task { @MainActor in exit(await perform(steps: .live)) }
    }

    /// Coduri: 0 = eliminată/inexistentă, 2 = după repornire, 1 = eroare.
    /// Orice eroare NEFilter oprește fluxul înaintea dezactivării extensiei,
    /// astfel încât SelfUninstaller să păstreze datele și aplicația.
    @MainActor
    static func perform(steps: Steps) async -> Int32 {
        say("→ Scot configurația de filtru de rețea…")
        let hasConfiguration: Bool
        do {
            hasConfiguration = try await steps.loadFilterConfiguration()
        } catch {
            say("  ✗ configurația filtrului nu a putut fi citită: \(error.localizedDescription)")
            return 1
        }

        if hasConfiguration {
            do {
                try await steps.removeFilterConfiguration()
                say("  ✓ configurația de filtru a fost scoasă")
            } catch {
                say("  ✗ configurația filtrului nu a putut fi eliminată: \(error.localizedDescription)")
                return 1
            }
        } else {
            say("  — nicio configurație de filtru")
        }

        say("→ Dezactivez extensia de rețea (macOS poate cere parola de administrator)…")
        switch await steps.deactivateExtension() {
        case .removed:
            say("  ✓ extensia de rețea a fost dezactivată")
            return 0
        case .removedAfterReboot:
            say("  ✓ extensia se elimină la următoarea repornire")
            return 2
        case .notInstalled:
            say("  — extensia nu era instalată")
            return 0
        case .failed(let reason):
            say("  ✗ \(reason)")
            return 1
        }
    }

    static func say(_ text: String) {
        print(text)
        fflush(stdout)
        log.info(text)
    }

    private final class Delegate: NSObject, OSSystemExtensionRequestDelegate {
        private var continuation: CheckedContinuation<DeactivationOutcome, Never>?

        init(continuation: CheckedContinuation<DeactivationOutcome, Never>) {
            self.continuation = continuation
        }

        private func finish(_ outcome: DeactivationOutcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }

        func request(_ request: OSSystemExtensionRequest,
                     actionForReplacingExtension existing: OSSystemExtensionProperties,
                     withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .cancel }

        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            UninstallMode.say("  … aștept confirmarea ta în fereastra macOS")
        }

        func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
            switch result {
            case .completed: finish(.removed)
            case .willCompleteAfterReboot: finish(.removedAfterReboot)
            @unknown default: finish(.failed("Rezultat necunoscut la dezactivarea extensiei."))
            }
        }

        func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
            let nsError = error as NSError
            if nsError.domain == OSSystemExtensionErrorDomain, nsError.code == OSSystemExtensionError.extensionNotFound.rawValue {
                finish(.notInstalled)
                return
            }
            finish(.failed(error.localizedDescription))
        }
    }
}

extension UninstallMode.Steps {
    @MainActor
    static var live: Self {
        let manager = NEFilterManager.shared()
        return Self(
            loadFilterConfiguration: {
                try await withCheckedThrowingContinuation { continuation in
                    manager.loadFromPreferences { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: manager.providerConfiguration != nil) }
                    }
                }
            },
            removeFilterConfiguration: {
                try await withCheckedThrowingContinuation { continuation in
                    manager.removeFromPreferences { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: ()) }
                    }
                }
            },
            deactivateExtension: {
                await withCheckedContinuation { continuation in
                    let delegate = UninstallMode.Delegate(continuation: continuation)
                    UninstallMode.activeDelegate = delegate
                    let id = (Bundle.main.bundleIdentifier ?? "dev.gordas.GDCFirewall") + ".extension"
                    let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: id, queue: .main)
                    request.delegate = delegate
                    OSSystemExtensionManager.shared.submitRequest(request)
                }
            })
    }
}
