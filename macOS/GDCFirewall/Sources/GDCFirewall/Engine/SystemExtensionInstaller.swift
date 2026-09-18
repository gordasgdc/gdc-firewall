import AppKit
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

    @Published private(set) var state: State = .unknown {
        didSet { if state != oldValue { log.info("Stare extensie: \(oldValue) → \(state)") } }
    }

    /// Etapa unei actualizări a extensiei, separată de `state` (care descrie
    /// filtrul). Vezi EngineService pentru cursa pe care o rezolvă.
    enum Phase: Equatable {
        case idle
        case replacing          // jobul vechi e scos, extensia nouă se activează
        case deferred           // înlocuirea amânată de utilizator: rulează extensia veche
        case needsReboot        // extensia nouă fără serviciul Mach: doar repornirea repară
    }

    @Published private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { log.info("Etapă actualizare: \(oldValue) → \(phase)") } }
    }

    /// Schimbările de filtru făcute de noi declanșează și ele notificarea
    /// NEFilterConfigurationDidChange; le ignorăm ca să nu reconectăm de două ori.
    private var lastOwnSave = Date.distantPast

    /// Mesajul de repornire apare O SINGURĂ DATĂ per versiune a extensiei, per
    /// lansare. (În 2.3.2 de test, o reparație care nu reușea cerea parola în
    /// buclă: 15 prompturi în 14 minute.)
    private var promptedLabel: String?
    private var ensuring = false

    private let log = DiagnosticLog("sysex")

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

    /// Înlocuire SECVENȚIALĂ (cauza: EngineService). Dacă rulează altă versiune
    /// a extensiei, jobul ei se scoate ÎNAINTE de activare; altfel macOS o
    /// înregistrează pe cea nouă fără serviciul Mach. Scoaterea cere o singură
    /// dată parola de administrator — actualizarea automată o face ea, ca root,
    /// înainte de relansare. Dacă utilizatorul refuză, aplicația folosește
    /// extensia veche (același motor, același protocol XPC) și propune din nou
    /// din meniu sau la următoarea pornire.
    func activate() {
        log.info("Cer activarea extensiei \(extensionBundleID)")
        state = .requesting
        Task { @MainActor in await self.activateSequentially() }
    }

    /// „Finalizează actualizarea motorului…”, după o amânare.
    @MainActor
    func finishEngineUpdate() {
        guard phase == .deferred else { return }
        Task { @MainActor in await self.activateSequentially() }
    }

    @MainActor
    private func activateSequentially() async {
        let bundled = EngineService.bundledLabel
        let stale = await Task.detached { EngineService.runningLabels() }.value.filter { $0 != bundled }
        if let bundled, !stale.isEmpty {
            log.info("Actualizare extensie: \(stale.joined(separator: ", ")) → \(bundled)")
            phase = .replacing
            _ = await UpdateGuard.engage()
            do {
                try await Task.detached { try EngineService.removeJobsWithAdmin(stale) }.value
            } catch {
                log.warning("Înlocuirea extensiei amânată: \(error.localizedDescription)")
                phase = .deferred
                UpdateGuard.release()
                enableFilter()
                return
            }
        }
        submitActivation()
    }

    private func submitActivation() {
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
        log.info("Înlocuiesc extensia \(existing.bundleShortVersion) (build \(existing.bundleVersion)) cu \(ext.bundleShortVersion) (build \(ext.bundleVersion))")
        return .replace
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
            // Sănătatea motorului (inclusiv după o înlocuire) se verifică din
            // filterEnabled(), când filtrul e confirmat pornit.
            enableFilter()
        case .willCompleteAfterReboot:
            state = .failed(L("Extensia se va activa după repornirea Mac-ului."))
        @unknown default:
            state = .failed(L("Rezultat necunoscut la activarea extensiei."))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Activarea extensiei a eșuat: \(error.localizedDescription)")
        state = .failed(error.localizedDescription)
    }

    // MARK: - Sănătatea motorului

    /// După activare (și după reconectări eșuate): jobul extensiei din pachet
    /// trebuie să dețină serviciul Mach. Cu înlocuirea secvențială asta e
    /// regula; dacă totuși nu (o înlocuire făcută de o versiune veche a
    /// aplicației), doar repornirea Mac-ului înregistrează extensia din nou —
    /// `kickstart` și `bootout` pe jobul nou NU repară (verificat, vezi
    /// EngineService). Nicio parolă, niciun ciclu: un singur mesaj.
    @MainActor
    private func ensureEngine() async {
        guard !ensuring, phase != .deferred, let label = EngineService.bundledLabel else { return }
        ensuring = true
        defer { ensuring = false }
        let wasReplacing = phase == .replacing

        await waitUntil(seconds: 30) { EngineService.runningLabels().allSatisfy { $0 == label } }
        // Procesul nou își pornește ascultătorul XPC la câteva zeci de ms după
        // activare: o primă citire „fără serviciul Mach” e normală (verificat —
        // alarmă falsă la 16 ms). Verdictul se dă abia după 10 s de așteptare.
        await waitUntil(seconds: 10) { EngineService.ownsMachService(label) == true }
        switch await probe(label) {
        case true?:
            if wasReplacing { log.info("Extensia nouă deține serviciul Mach — înlocuire curată") }
            phase = .idle
            if wasReplacing { DaemonBridge.shared.reconnectNow() }
        case false?:
            log.error("\(label) rulează fără serviciul Mach — se repară la repornirea Mac-ului")
            phase = .needsReboot
            promptReboot()
        case nil:
            log.error("Filtrul e pornit, dar \(label) lipsește din launchd — se repară la repornirea Mac-ului")
            phase = .needsReboot
            promptReboot()
        }
    }

    /// Verificarea de sănătate după reconectări eșuate (ex. o versiune
    /// instalată manual, peste una care rula).
    @MainActor
    func checkEngineHealth() {
        guard phase == .idle, state == .active else { return }
        Task { @MainActor in await self.ensureEngine() }
    }

    @MainActor
    private func promptReboot() {
        guard let label = EngineService.bundledLabel, promptedLabel != label else { return }
        promptedLabel = label
        let alert = NSAlert()
        alert.messageText = L("Repornește Mac-ul ca să finalizezi actualizarea filtrului")
        alert.informativeText = UpdateGuard.isEngaged
            ? L("macOS a pornit noua versiune a filtrului fără legătura cu aplicația. Regulile tale se aplică în continuare, iar conexiunile noi sunt blocate până la repornire.")
            : L("macOS a pornit noua versiune a filtrului fără legătura cu aplicația. Regulile tale se aplică în continuare, dar conexiunile noi sunt permise automat până la repornire.")
        alert.addButton(withTitle: L("Am înțeles"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func probe(_ label: String) async -> Bool? {
        await Task.detached { EngineService.ownsMachService(label) }.value
    }

    @discardableResult
    private func waitUntil(seconds: Int, _ condition: @escaping @Sendable () -> Bool) async -> Bool {
        for _ in 0..<(seconds * 2) {
            if await Task.detached(operation: condition).value { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
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
        lastOwnSave = Date()
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
        guard Date().timeIntervalSince(lastOwnSave) > 3 else { return }
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let now: State = manager.isEnabled ? .active : .filterOff
                guard now != self.state else { return }
                self.log.info("Filtrul a fost \(manager.isEnabled ? "pornit" : "oprit") din afara aplicației")
                if now == .active { self.filterEnabled() } else { self.state = now }
            }
        }
    }

    private func filterEnabled() {
        log.info("Filtrul de rețea e pornit")
        state = .active
        // Daemon-ul abia acum începe să accepte conexiuni XPC.
        DaemonBridge.shared.reconnect()
        Task { @MainActor in await self.ensureEngine() }
    }

    /// Include refuzul utilizatorului la promptul de filtrare — se vede în
    /// meniu, nu doar în log.
    private func filterFailed(_ step: String, _ error: Error) {
        log.error("Filtrul de rețea: \(step) a eșuat: \(error.localizedDescription)")
        state = .failed(error.localizedDescription)
    }
}
