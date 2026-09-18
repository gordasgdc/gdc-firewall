import Foundation
import os.log

/// Puntea dintre interfața GDC și daemon-ul LuLu.
///
/// Legătura e BIDIRECȚIONALĂ, nu „cerem și primim”: noi apelăm
/// `XPCDaemonProtocol` pentru reguli și preferințe, iar daemon-ul ne
/// apelează pe noi prin `XPCUserProtocol` când apare o conexiune nouă.
/// De-asta clasa exportă un obiect, nu doar consumă unul.
///
/// Tot ce trece pe aici e traducere de date. Nicio decizie de filtrare nu
/// trăiește în stratul GDC — ea rămâne în extensia de rețea, neatinsă.
final class DaemonBridge: NSObject, ObservableObject, XPCUserProtocol {
    static let shared = DaemonBridge()

    private let log = DiagnosticLog("bridge")

    @Published private(set) var rules: [FirewallRule] = []
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    /// Alertele în așteptare. Interfața o arată pe prima; restul stau la
    /// coadă, ca utilizatorul să nu primească un teanc de ferestre.
    @Published private(set) var pendingAlerts: [ConnectionRequest] = []

    /// Domenii oprite de blocklist în sesiunea curentă — jurnal pentru
    /// Rules Manager, cu opțiunea de a le trece pe lista de excepții.
    @Published private(set) var blockedByList: Set<String> = []

    private var connection: NSXPCConnection?

    /// Daemon-ul poate dispărea și reveni: înlocuirea extensiei la update,
    /// repornire după o cădere, trezire din sleep. Fără reconectare, meniul
    /// rămâne pe „Motor oprit” deși filtrul rulează. Așteptarea crește până
    /// la un minut, ca un daemon absent să nu fie căutat în buclă strânsă.
    private var reconnectItem: DispatchWorkItem?
    private var reconnectDelay: TimeInterval = 2

    /// Reconectări eșuate la rând. Cu filtrul pornit și daemon-ul de negăsit
    /// minute în șir, cauza cunoscută e înlocuirea extensiei: versiunea nouă
    /// n-a putut prelua serviciul Mach de la cea veche (CLAUDE.md, v2.0.4) și
    /// doar repornirea Mac-ului o deblochează.
    @Published private(set) var failedReconnects = 0
    static let restartHintThreshold = 5

    /// Blocurile de răspuns, ținute pe `uuid`-ul alertei. Fiecare TREBUIE
    /// apelat exact o dată: dacă pierdem blocul, extensia ține conexiunea
    /// de rețea suspendată până expiră, iar utilizatorul vede „internetul
    /// nu merge”, fără nicio fereastră care să explice de ce.
    private var replies: [String: ([AnyHashable: Any]) -> Void] = [:]

    private override init() { super.init() }

    // MARK: - Conexiune

    func connect() {
        log.info("Conectare la daemon: \(LuLu.daemonMachService)")
        let conn = NSXPCConnection(machServiceName: LuLu.daemonMachService, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: XPCDaemonProtocol.self)

        // Obiectul exportat e cel prin care daemon-ul ne trimite alertele.
        conn.exportedInterface = NSXPCInterface(with: XPCUserProtocol.self)
        conn.exportedObject = self

        // O conexiune XPC care eșuează la lookup e invalidată DEFINITIV și
        // nu se reconectează singură (vezi comentariul din
        // `XPCDaemonClient.m`, metoda `reconnect`). O aruncăm și facem una
        // nouă, nu încercăm s-o reînviem.
        conn.invalidationHandler = { [weak self, weak conn] in
            self?.log.error("Conexiunea XPC cu daemon-ul a fost invalidată (\(LuLu.daemonMachService))")
            DispatchQueue.main.async {
                // O conexiune veche, deja înlocuită, nu atinge starea curentă.
                guard let self, self.connection === conn else { return }
                self.connection = nil
                self.isConnected = false
                self.scheduleReconnect()
            }
        }
        conn.interruptionHandler = { [weak self, weak conn] in
            self?.log.error("Conexiunea XPC cu daemon-ul a fost întreruptă")
            DispatchQueue.main.async {
                guard let self, self.connection === conn else { return }
                self.isConnected = false
                self.scheduleReconnect()
            }
        }

        conn.resume()
        connection = conn

        proxy?.checkIn { [weak self] ready in
            self?.log.info("checkIn la daemon: \(ready ? "acceptat" : "refuzat")")
            DispatchQueue.main.async {
                if ready {
                    self?.reconnectDelay = 2
                    self?.failedReconnects = 0
                    // Motorul poate fi proaspăt (extensie nouă, repornire):
                    // îi retrimitem blocklist-ul la fiecare conectare.
                    BlocklistStore.shared.applyToEngine()
                    Task { @MainActor in UpdateGuard.releaseIfSafe() }
                }
                self?.isConnected = ready
                if ready { self?.reloadRules() }
            }
        }
    }

    /// După o înlocuire sau o repornire a motorului: reîncercări rapide, de la zero.
    func reconnectNow() {
        reconnectDelay = 1
        failedReconnects = 0
        reconnect()
    }

    func reconnect() {
        reconnectItem?.cancel()
        reconnectItem = nil
        // Invalidarea noastră nu e o cădere: fără handler-e, nu programează
        // încă o reconectare (altfel fiecare reconectare ar naște alta).
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        connect()
    }

    private func scheduleReconnect() {
        guard reconnectItem == nil else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 60)
        failedReconnects += 1
        if failedReconnects == Self.restartHintThreshold {
            Task { @MainActor in SystemExtensionInstaller.shared.checkEngineHealth() }
        }
        log.info("Reconectare la daemon în \(Int(delay)) s")
        let item = DispatchWorkItem { [weak self] in
            self?.reconnectItem = nil
            self?.reconnect()
        }
        reconnectItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private var proxy: XPCDaemonProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.log.error("Apel XPC eșuat: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self?.lastError = error.localizedDescription
                self?.isConnected = false
            }
        } as? XPCDaemonProtocol
    }

    // MARK: - Reguli

    func reloadRules() {
        proxy?.getRules { [weak self] archived in
            let decoded = Self.decodeRules(archived)
            self?.log.info("Reguli încărcate din motor: \(decoded.count)")
            DispatchQueue.main.async { self?.rules = decoded }
        }
    }

    // MARK: - Acțiuni pe reguli (tabel, meniu contextual, inspector)

    /// Schimbă acțiunea regulii EXISTENTE (ștergere + adăugare cu aceleași
    /// câmpuri). Înainte se adăuga o regulă nouă pe tot procesul, iar cea
    /// veche rămânea lângă ea.
    func setAction(_ action: RuleAction, for rule: FirewallRule) {
        log.info("Regulă schimbată de utilizator: \(rule.enginePath) → \(action == .allow ? "permis" : "blocat")")
        replace(rule, with: rule.engineInfo(action: action))
    }

    func setEnabled(_ enabled: Bool, for rules: [FirewallRule]) {
        guard let proxy else { return }
        for rule in rules {
            proxy.toggleRule(rule.engineKey, rule: rule.uuid,
                             state: NSNumber(value: enabled ? LuLu.RuleToggle.enable : LuLu.RuleToggle.disable))
        }
        log.info("\(enabled ? "Activate" : "Dezactivate"): \(rules.count) reguli")
        reloadRules()
    }

    func add(_ info: [String: Any]) {
        log.info("Regulă nouă: \(info[LuLu.Key.path] ?? "?") → \(info[LuLu.Key.endpointAddr] ?? "*"):\(info[LuLu.Key.endpointPort] ?? "*")")
        proxy?.addRule(info)
        reloadRules()
    }

    /// Ștergere + adăugare, pe aceeași conexiune XPC: motorul le primește în ordine.
    func replace(_ rule: FirewallRule, with info: [String: Any]) {
        guard let proxy else { return }
        proxy.deleteRule(rule.engineKey, rule: rule.uuid)
        proxy.addRule(info)
        reloadRules()
    }

    func duplicate(_ rule: FirewallRule) { add(rule.engineInfo()) }

    /// Aceeași destinație și acțiune, pentru toate procesele (calea `*`).
    func makeGlobal(_ rule: FirewallRule) { add(rule.engineInfo(path: "*")) }

    /// Executabil mutat/redenumit: regula trece pe calea nouă.
    func repairPath(of rule: FirewallRule, to path: String) {
        log.info("Cale reparată: \(rule.enginePath) → \(path)")
        replace(rule, with: rule.engineInfo(path: path))
    }

    /// O regulă pasivă (creată fără decizia utilizatorului) devine regula lui.
    func approve(_ rules: [FirewallRule]) {
        for rule in rules where rule.isUnapproved { replace(rule, with: rule.engineInfo()) }
        log.info("Aprobate: \(rules.count) reguli")
    }

    func delete(_ rule: FirewallRule) { delete([rule]) }

    func delete(_ rules: [FirewallRule]) {
        // `deleteRule` cere ȘI cheia, ȘI uuid-ul regulii — a doua fiindcă un
        // binar poate avea mai multe reguli, câte una per destinație.
        for rule in rules {
            log.info("Regulă ștearsă: \(rule.enginePath) (\(rule.endpointAddr):\(rule.endpointPort))")
            proxy?.deleteRule(rule.engineKey, rule: rule.uuid)
        }
        let ids = Set(rules.map(\.id))
        self.rules.removeAll { ids.contains($0.id) }
    }

    // MARK: - Preferințele motorului

    func preferences() async -> [String: Any]? {
        guard let proxy else { return nil }
        // Un daemon care nu răspunde n-ar apela niciodată blocul: timeout de 3 s.
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            proxy.getPreferences { prefs in once.resume(prefs as? [String: Any]) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.resume(nil) }
        }
    }

    /// Blocklist-ul, lista de excepții etc. — aplicate de motor fiecărei
    /// conexiuni, nu doar celor care ajung la o alertă.
    func updatePreferences(_ preferences: [String: Any]) {
        guard let proxy else {
            log.warning("Preferințe netrimise (motor neconectat): \(preferences.keys.sorted())")
            return
        }
        proxy.updatePreferences(preferences) { [weak self] _ in
            self?.log.info("Preferințe aplicate în motor: \(preferences.keys.sorted().joined(separator: ", "))")
        }
    }

    /// Import: câte un `addRule` per regulă, calea pe care o folosesc și
    /// alertele. `importRules:userOnly:` al motorului ar ÎNLOCUI toate regulile
    /// utilizatorului — un al doilea import l-ar șterge pe primul.
    /// Motorul calculează singur semnătura binarului, din calea de pe disc.
    func addImportedRules(_ infos: [[String: Any]]) {
        guard let proxy else { return }
        for info in infos { proxy.addRule(info) }
        log.info("Import: \(infos.count) reguli trimise motorului")
        reloadRules()
    }

    /// Semnăturile regulilor existente, ca un import repetat să nu dubleze.
    var ruleSignatures: Set<String> {
        Set(rules.map { Self.signature(path: $0.enginePath, addr: $0.endpointAddr,
                                       port: $0.endpointPort, action: $0.action.rawValue) })
    }

    static func signature(path: String, addr: String, port: String, action: Int) -> String {
        "\(path)|\(addr)|\(port)|\(action)"
    }

    // MARK: - XPCUserProtocol (daemon-ul ne apelează pe noi)

    func rulesChanged() {
        DispatchQueue.main.async { [weak self] in self?.reloadRules() }
    }

    func alertShow(_ alert: [AnyHashable: Any], reply: @escaping ([AnyHashable: Any]) -> Void) {
        guard let request = ConnectionRequest(alert: alert) else {
            // Un dicționar pe care nu-l înțelegem NU se abandonează tăcut:
            // blocul de răspuns trebuie apelat, altfel conexiunea rămâne
            // suspendată. Îl lăsăm să treacă și logăm — un firewall care
            // taie internetul din cauza unui câmp lipsă e mai rău decât unul
            // care ratează o alertă.
            log.error("Alertă neinterpretabilă: \(String(describing: alert))")
            var response = alert
            response[LuLu.Key.action] = LuLu.RuleState.allow
            response[LuLu.Key.duration] = LuLu.Duration.once
            reply(response)
            return
        }

        log.info("Alertă: \(request.processName) [\(request.path)] → \(request.remoteHost):\(request.remotePort)"
            + " · risc \(request.risk) · pid \(request.processID)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.replies[request.uuid] = reply
            self.enqueue(request)
        }
    }

    // MARK: - Alerte

    private func enqueue(_ request: ConnectionRequest) {
        // Ordinea contează. Blocklist-ul e PRIMUL, înaintea Auto-Pilot:
        // altfel un proces semnat Apple (aprobat tăcut) ar putea suna un
        // domeniu de telemetrie aflat pe listă, adică exact cazul pe care
        // nivelul „Minim” există să-l prindă.
        if BlocklistStore.shared.isBlocked(request.remoteHost) {
            blockedByList.insert(request.remoteHost)
            // Scope `endpoint`, nu `process`: blocăm destinația, nu aplicația.
            submit(AlertVerdict(request: request, action: .block, remember: false, origin: .baseline), scope: LuLu.ActionScope.endpoint)
            return
        }
        if let verdict = AutoPilot.shared.verdict(for: request) {
            submit(verdict)
            return
        }
        pendingAlerts.append(request)
    }

    /// Trimite verdictul înapoi motorului. Răspunsul e o COPIE a alertei
    /// primite, îmbogățită — exact cum face aplicația originală: dicționarul
    /// poartă câmpuri interne pe care noi nu le citim, dar motorul le
    /// așteaptă înapoi neschimbate.
    func submit(_ verdict: AlertVerdict, scope: Int = LuLu.ActionScope.process) {
        let request = verdict.request
        defer {
            pendingAlerts.removeAll { $0.id == request.id }
            replies[request.uuid] = nil
        }
        guard let reply = replies[request.uuid] else {
            log.error("Verdict fără bloc de răspuns pentru \(request.uuid)")
            return
        }

        var response = request.rawAlert
        response[LuLu.Key.type] = LuLu.RuleType.user
        response[LuLu.Key.userID] = Int(getuid())
        response[LuLu.Key.action] = verdict.action.rawValue
        response[LuLu.Key.scope] = scope
        response[LuLu.Key.duration] = verdict.remember ? LuLu.Duration.always : LuLu.Duration.once
        response[LuLu.Key.endpointAddr] = request.remoteAddress

        log.info("Verdict \(verdict.action == .allow ? "PERMIS" : "BLOCAT"): \(request.processName) → \(request.remoteHost):\(request.remotePort)"
            + " · origine \(verdict.origin) · ține minte: \(verdict.remember ? "da" : "nu")")
        reply(response)
        if verdict.remember { reloadRules() }
    }

    func allowFromBlocklist(_ host: String) {
        BlocklistStore.shared.allow(host)
        blockedByList.remove(host)
    }

    // MARK: - Traducere reguli

    /// Arhiva conține obiecte `Rule` — clasă Objective-C a motorului. Le
    /// citim prin KVC, nu prin cast: stratul GDC nu redeclară clasa
    /// motorului, ca o schimbare de câmp acolo să nu devină un crash aici.
    ///
    /// Funcționează doar când binarul e linkat împreună cu motorul (vezi
    /// modelul de integrare din CLAUDE.md, Partea 2). Rulat din pachetul
    /// SPM de dezvoltare a interfeței, `Rule` nu există în runtime, iar
    /// dezarhivarea eșuează — pe bună dreptate, și o spunem explicit.
    static func decodeRules(_ archived: Data) -> [FirewallRule] {
        guard !archived.isEmpty else { return [] }
        let allowed: [AnyClass] = [
            NSDictionary.self, NSArray.self, NSString.self,
            NSNumber.self, NSSet.self, NSDate.self
        ] + (NSClassFromString("Rule").map { [$0] } ?? [])

        guard let root = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: allowed, from: archived
        ) as? [String: Any] else { return [] }

        // Structura reală (verificată pe rules.plist): { cheie: { rules: [Rule],
        // signingInfo, paths } }. Cheia e de regulă „semnătură:autoritate”,
        // nu calea — calea vine din fiecare regulă.
        return root.flatMap { key, value -> [FirewallRule] in
            guard let entry = value as? [String: Any],
                  let objects = entry["rules"] as? [AnyObject] else { return [] }
            return objects.compactMap { object in
                let path = object.value(forKey: "path") as? String ?? key
                return FirewallRule(engineRule: object, path: path, key: key)
            }
        }
    }
}

/// Reia o continuare O SINGURĂ dată — răspunsul XPC și timeout-ul se întrec.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: Any]?, Never>?

    init(_ continuation: CheckedContinuation<[String: Any]?, Never>) { self.continuation = continuation }

    func resume(_ value: [String: Any]?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
