import Foundation
import SystemExtensions
import os.log

/// Cere macOS-ului să activeze extensia de rețea a motorului.
///
/// E scrisă de la zero, nu preluată din `LuLu/App/Extension.m`: ținta App a
/// motorului nu mai e compilată (a fost înlocuită de interfața GDC), iar
/// codul original e legat de `AppDelegate`-ul lui. Extensia PROPRIU-ZISĂ
/// rămâne neatinsă — aici doar o pornim.
///
/// Pasul ăsta e cel pe care utilizatorul trebuie să-l aprobe manual în
/// Setări de sistem. Până atunci aplicația pare pornită și nu filtrează
/// nimic, de aceea `state` e publicat și arătat în interfață, nu înghițit.
final class SystemExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let shared = SystemExtensionInstaller()

    enum State: Equatable {
        case unknown
        case requesting
        case needsApproval      // utilizatorul trebuie să apese „Permite” în Setări
        case active
        case failed(String)

        var isProtecting: Bool { self == .active }
    }

    @Published private(set) var state: State = .unknown

    private let log = Logger(subsystem: "dev.gordas.GDCFirewall", category: "sysex")

    /// Trebuie să fie identificatorul extensiei din proiect
    /// (`dev.gordas.GDCFirewall.extension`) — îl citim din bundle, ca să nu
    /// existe două locuri care trebuie ținute sincronizate manual.
    private var extensionBundleID: String {
        (Bundle.main.bundleIdentifier ?? "dev.gordas.GDCFirewall") + ".extension"
    }

    func activate() {
        state = .requesting
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    /// La reinstalare/actualizare, înlocuim mereu versiunea veche. Un prompt
    /// „vrei să înlocuiești?” la fiecare update ar fi zgomot pentru un
    /// utilizator care tocmai a apăsat „Actualizează acum”.
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.info("Extensia așteaptă aprobarea utilizatorului")
        state = .needsApproval
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            state = .active
            // Daemon-ul abia acum începe să accepte conexiuni XPC.
            DaemonBridge.shared.reconnect()
        case .willCompleteAfterReboot:
            state = .failed("Extensia se va activa după repornirea Mac-ului.")
        @unknown default:
            state = .failed("Rezultat necunoscut la activarea extensiei.")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Activarea extensiei a eșuat: \(error.localizedDescription, privacy: .public)")
        state = .failed(error.localizedDescription)
    }
}
