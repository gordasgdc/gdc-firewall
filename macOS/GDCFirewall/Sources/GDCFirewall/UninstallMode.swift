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
    private static let delegate = Delegate()

    @MainActor
    static func run() {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { say("  ✗ timp depășit"); exit(1) }
        say("→ Scot configurația de filtru de rețea…")
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { _ in
            DispatchQueue.main.async {
                guard manager.providerConfiguration != nil else {
                    say("  — nicio configurație de filtru")
                    deactivate()
                    return
                }
                manager.removeFromPreferences { error in
                    DispatchQueue.main.async {
                        say(error.map { "  ✗ \($0.localizedDescription)" } ?? "  ✓ configurația de filtru a fost scoasă")
                        deactivate()
                    }
                }
            }
        }
    }

    @MainActor
    private static func deactivate() {
        say("→ Dezactivez extensia de rețea (macOS poate cere parola de administrator)…")
        let id = (Bundle.main.bundleIdentifier ?? "dev.gordas.GDCFirewall") + ".extension"
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: id, queue: .main)
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    static func say(_ text: String) {
        print(text)
        fflush(stdout)
        log.info(text)
    }

    private final class Delegate: NSObject, OSSystemExtensionRequestDelegate {
        func request(_ request: OSSystemExtensionRequest,
                     actionForReplacingExtension existing: OSSystemExtensionProperties,
                     withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .cancel }

        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            UninstallMode.say("  … aștept confirmarea ta în fereastra macOS")
        }

        func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
            switch result {
            case .completed: UninstallMode.say("  ✓ extensia de rețea a fost dezactivată"); exit(0)
            case .willCompleteAfterReboot: UninstallMode.say("  ✓ extensia se elimină la următoarea repornire"); exit(2)
            @unknown default: exit(1)
            }
        }

        func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
            let nsError = error as NSError
            if nsError.domain == OSSystemExtensionErrorDomain, nsError.code == OSSystemExtensionError.extensionNotFound.rawValue {
                UninstallMode.say("  — extensia nu era instalată")
                exit(0)
            }
            UninstallMode.say("  ✗ \(error.localizedDescription)")
            exit(1)
        }
    }
}
