import Foundation
import Combine

/// Modul Silențios (Aprobare inteligentă) — ACTIVAT IMPLICIT.
///
/// Motivul e unul singur: un firewall care întreabă de 40 de ori în prima
/// oră e un firewall pe care omul îl dezinstalează. Procesele semnate
/// oficial de Apple (`com.apple.*`) sunt aprobate tăcut și trec într-un
/// jurnal, nu într-un pop-up. Tot ce NU e Apple rămâne întrebat, mereu —
/// Auto-Pilot nu aprobă niciodată ceva nesemnat sau necunoscut.
final class AutoPilot: ObservableObject {
    static let shared = AutoPilot()

    private static let enabledKey = "GDCFirewall.autoPilot.enabled"
    private static let logKey = "GDCFirewall.autoPilot.log"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Ce a aprobat singur, ca utilizatorul să poată verifica oricând.
    /// Nu e un secret al aplicației, e un jurnal vizibil în Rules Manager.
    @Published private(set) var silentlyApproved: [String] = []

    private init() {
        let defaults = UserDefaults.standard
        // `object(forKey:)` (nu `bool(forKey:)`) — altfel prima pornire,
        // unde cheia încă nu există, ar citi `false` și ar porni cu
        // Auto-Pilot OPRIT, exact invers față de cerință.
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        silentlyApproved = defaults.stringArray(forKey: Self.logKey) ?? []
    }

    /// `nil` = Auto-Pilot nu se pronunță, alerta merge la utilizator.
    func verdict(for request: ConnectionRequest) -> AlertVerdict? {
        guard isEnabled else { return nil }
        guard qualifies(request) else { return nil }
        record(request.friendlyName)
        return AlertVerdict(request: request, action: .allow, remember: true, origin: .autoPilot)
    }

    /// Dublă condiție, deliberat: bundle ID `com.apple.*` NU e suficient
    /// singur — oricine poate scrie asta în propriul Info.plist. Semnătura
    /// verificată de motor e cea care decide.
    private func qualifies(_ request: ConnectionRequest) -> Bool {
        guard request.isAppleSigned else { return false }
        guard let bundleID = request.bundleID else {
            // Daemon de sistem fără bundle ID, dar semnat Apple și pornit
            // din interiorul sistemului — acceptat.
            return request.path.hasPrefix("/usr/libexec/")
                || request.path.hasPrefix("/System/")
                || request.path.hasPrefix("/usr/sbin/")
        }
        return bundleID.hasPrefix("com.apple.")
    }

    private func record(_ name: String) {
        guard !silentlyApproved.contains(name) else { return }
        silentlyApproved.append(name)
        UserDefaults.standard.set(silentlyApproved, forKey: Self.logKey)
    }

    func clearLog() {
        silentlyApproved = []
        UserDefaults.standard.removeObject(forKey: Self.logKey)
    }
}
