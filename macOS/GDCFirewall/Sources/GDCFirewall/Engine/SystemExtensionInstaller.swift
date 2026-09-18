import Foundation
import SystemExtensions
import NetworkExtension
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
        case filterOff          // extensie instalată, filtrare oprită (din meniu sau din Setări)
        case failed(String)

        var isProtecting: Bool { self == .active }
    }

    @Published private(set) var state: State = .unknown

    private let log = Logger(subsystem: "dev.gordas.GDCFirewall", category: "sysex")

    private override init() {
        super.init()
        // Filtrul se poate opri și din Setări de sistem → Rețea → Filtre; fără
        // observatorul ăsta meniul ar spune „Protecție activă” la nesfârșit.
        NotificationCenter.default.addObserver(
            forName: .NEFilterConfigurationDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshFilterState()
        }
    }

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
            // Extensie instalată ≠ filtru pornit: fără o configurație
            // NEFilterManager activă, macOS nici nu lansează procesul extensiei.
            enableFilter()
        case .willCompleteAfterReboot:
            state = .failed(L("Extensia se va activa după repornirea Mac-ului."))
        @unknown default:
            state = .failed(L("Rezultat necunoscut la activarea extensiei."))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Activarea extensiei a eșuat: \(error.localizedDescription, privacy: .public)")
        state = .failed(error.localizedDescription)
    }

    // MARK: - Filtrul de conținut

    /// Port al `toggleNetworkExtension:` din `App/Extension.m` al motorului,
    /// fișier scos din țintă odată cu interfața LuLu: filtrare pe socket-uri,
    /// fără pachete. Prima salvare afișează promptul macOS
    /// „GDC Firewall ar dori să filtreze conținutul de rețea”.
    ///
    /// La prima configurare filtrul se pornește singur. După aceea, o oprire
    /// făcută de utilizator (meniu sau Setări) se respectă și la relansare —
    /// altfel aplicația l-ar reporni peste decizia lui.
    private func enableFilter() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.filterFailed("încărcarea configurației", error)
                    return
                }
                if manager.isEnabled {
                    self.filterEnabled()
                } else if manager.providerConfiguration != nil {
                    self.log.info("Filtrul a fost oprit de utilizator; nu-l repornesc")
                    self.state = .filterOff
                } else {
                    self.save(manager, enabled: true)
                }
            }
        }
    }

    /// Comutatorul din meniu.
    func setFilterEnabled(_ enabled: Bool) {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.filterFailed("încărcarea configurației", error)
                } else {
                    self.save(manager, enabled: enabled)
                }
            }
        }
    }

    private func save(_ manager: NEFilterManager, enabled: Bool) {
        if manager.providerConfiguration == nil {
            let config = NEFilterProviderConfiguration()
            config.filterPackets = false
            config.filterSockets = true
            manager.providerConfiguration = config
        }
        manager.localizedDescription = "GDC Firewall"
        manager.isEnabled = enabled
        manager.saveToPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.filterFailed("salvarea configurației", error)
                } else if enabled {
                    self.filterEnabled()
                } else {
                    self.log.info("Filtrul de rețea e oprit")
                    self.state = .filterOff
                }
            }
        }
    }

    /// Doar după ce extensia e instalată: înainte, starea e a cererii de activare.
    private func refreshFilterState() {
        guard state == .active || state == .filterOff else { return }
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let now: State = manager.isEnabled ? .active : .filterOff
                guard now != self.state else { return }
                self.log.info("Filtrul a fost \(manager.isEnabled ? "pornit" : "oprit", privacy: .public) din afara aplicației")
                if now == .active { self.filterEnabled() } else { self.state = now }
            }
        }
    }

    private func filterEnabled() {
        log.info("Filtrul de rețea e pornit")
        state = .active
        // Daemon-ul abia acum începe să accepte conexiuni XPC.
        DaemonBridge.shared.reconnect()
    }

    /// Include refuzul utilizatorului la promptul de filtrare — se vede în
    /// meniu, nu doar în log.
    private func filterFailed(_ step: String, _ error: Error) {
        log.error("Filtrul de rețea: \(step, privacy: .public) a eșuat: \(error.localizedDescription, privacy: .public)")
        state = .failed(error.localizedDescription)
    }
}
