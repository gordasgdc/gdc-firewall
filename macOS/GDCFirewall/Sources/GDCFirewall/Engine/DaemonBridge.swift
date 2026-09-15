import Foundation
import os.log

/// Protocolul XPC expus de daemon-ul LuLu. E declarat aici DOAR ca să-l
/// putem apela din Swift — semnăturile trebuie să rămână identice cu cele
/// din motor (`Engine/LuLu/LuLu/Daemon/XPCDaemonProtocol.h`). Dacă motorul
/// se actualizează la un tag nou, `scripts/fetch-engine.sh` semnalează
/// diferența; adaptarea se face AICI, niciodată în motor.
@objc protocol EngineDaemonProtocol {
    func getPreferences(reply: @escaping ([String: Any]) -> Void)
    func updatePreferences(_ preferences: [String: Any])
    func getRules(reply: @escaping ([[String: Any]]) -> Void)
    func addRule(_ info: [String: Any])
    func deleteRule(_ path: String)
    func alertReply(_ reply: [String: Any])
}

/// Adaptor între interfața GDC și motor. Tot ce trece pe aici e traducere
/// de date — niciun pic de logică de filtrare nu trăiește în stratul GDC.
final class DaemonBridge: NSObject, ObservableObject {
    static let shared = DaemonBridge()

    private let machServiceName = "com.objective-see.lulu"
    private let log = Logger(subsystem: "dev.gordas.GDCFirewall", category: "bridge")

    @Published private(set) var rules: [FirewallRule] = []
    @Published private(set) var isConnected = false

    private var connection: NSXPCConnection?

    /// Alertele sosite de la motor, în ordinea în care au venit. UI-ul
    /// afișează prima din coadă; restul așteaptă, ca să nu îngropăm
    /// utilizatorul sub ferestre suprapuse.
    @Published private(set) var pendingAlerts: [ConnectionRequest] = []

    private override init() { super.init() }

    // MARK: - Conexiune

    func connect() {
        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: EngineDaemonProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.isConnected = false }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.isConnected = false }
        }
        conn.resume()
        connection = conn
        isConnected = true
        reloadRules()
    }

    private var proxy: EngineDaemonProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.log.error("XPC a eșuat: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self?.isConnected = false }
        } as? EngineDaemonProtocol
    }

    // MARK: - Reguli

    func reloadRules() {
        proxy?.getRules { [weak self] raw in
            let mapped = raw.compactMap(Self.rule(from:))
            DispatchQueue.main.async { self?.rules = mapped }
        }
    }

    func setAction(_ action: RuleAction, for rule: FirewallRule) {
        proxy?.addRule(["path": rule.enginePath, "action": action.rawValue])
        if let index = rules.firstIndex(of: rule) {
            rules[index].action = action
            rules[index].origin = .user
        }
    }

    func delete(_ rule: FirewallRule) {
        proxy?.deleteRule(rule.enginePath)
        rules.removeAll { $0.id == rule.id }
    }

    // MARK: - Alerte

    /// Trimite verdictul înapoi motorului și, dacă e cazul, întreabă de reguli.
    func submit(_ verdict: AlertVerdict) {
        proxy?.alertReply([
            "path": verdict.request.path,
            "pid": Int(verdict.request.processID),
            "action": verdict.action.rawValue,
            "temporary": !verdict.remember
        ])
        pendingAlerts.removeAll { $0.id == verdict.request.id }
        if verdict.remember { reloadRules() }
    }

    func enqueue(_ request: ConnectionRequest) {
        // Ordinea contează. Blocklist-ul e PRIMUL, înaintea Auto-Pilot:
        // altfel un proces semnat Apple (aprobat tăcut) ar putea suna un
        // domeniu de telemetrie aflat pe listă, adică exact cazul pe care
        // nivelul „Minim” există să-l prindă.
        if BlocklistStore.shared.isBlocked(request.remoteHost) {
            blockedByList.insert(request.remoteHost)
            submit(AlertVerdict(request: request, action: .block, remember: false, origin: .baseline))
            return
        }
        // Auto-Pilot răspunde înainte ca alerta să ajungă vreodată pe ecran.
        if let verdict = AutoPilot.shared.verdict(for: request) {
            submit(verdict)
            return
        }
        pendingAlerts.append(request)
    }

    /// Domenii oprite de listă în sesiunea curentă — apar în Rules Manager
    /// ca jurnal, cu opțiunea de a le trece pe lista de excepții.
    @Published private(set) var blockedByList: Set<String> = []

    // MARK: - Traducere

    private static func rule(from raw: [String: Any]) -> FirewallRule? {
        guard let path = raw["path"] as? String else { return nil }
        let bundleID = raw["bundleID"] as? String
        let name = raw["name"] as? String
        let appleSigned = raw["isApple"] as? Bool ?? false
        return FirewallRule(
            id: path,
            enginePath: path,
            bundleID: bundleID,
            friendlyName: ProcessCatalog.shared.friendlyName(
                processName: (path as NSString).lastPathComponent,
                bundleID: bundleID,
                displayName: name
            ),
            action: RuleAction(rawValue: raw["action"] as? Int ?? 0) ?? .block,
            origin: RuleOrigin(rawValue: raw["origin"] as? Int ?? 0) ?? .user,
            isAppleSigned: appleSigned,
            isNotarized: raw["isNotarized"] as? Bool ?? appleSigned,
            lastConnection: (raw["lastSeen"] as? Double).map { Date(timeIntervalSince1970: $0) },
            connectionCount: raw["count"] as? Int ?? 0
        )
    }
}
