import Foundation

/// O cerere de conexiune, construită din dicționarul pe care daemon-ul ni-l
/// trimite prin `alertShow:reply:`. `rawAlert` e păstrat INTEGRAL fiindcă
/// răspunsul trebuie să fie o copie îmbogățită a lui: dicționarul poartă
/// câmpuri interne ale motorului pe care nu le citim, dar care trebuie să
/// se întoarcă neschimbate.
struct ConnectionRequest: Identifiable, Hashable {
    let id: UUID
    let uuid: String             // KEY_UUID — cheia sub care motorul ține alerta
    let rawAlert: [AnyHashable: Any]
    let processID: pid_t
    let path: String
    let bundleID: String?
    let displayName: String?
    let remoteHost: String       // nume DNS dacă există, altfel IP
    let remoteAddress: String
    let remotePort: Int
    let isAppleSigned: Bool
    let isNotarized: Bool
    let arrivedAt: Date

    static func == (a: ConnectionRequest, b: ConnectionRequest) -> Bool { a.uuid == b.uuid }
    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }

    init?(alert: [AnyHashable: Any]) {
        guard let uuid = alert[LuLu.Key.uuid] as? String,
              let path = alert[LuLu.Key.path] as? String else { return nil }

        self.id = UUID()
        self.uuid = uuid
        self.rawAlert = alert
        self.path = path
        self.processID = pid_t((alert[LuLu.Key.pid] as? Int) ?? -1)
        self.displayName = alert[LuLu.Key.name] as? String
        self.remoteAddress = (alert[LuLu.Key.endpointAddr] as? String) ?? "necunoscut"
        self.remotePort = Int((alert[LuLu.Key.endpointPort] as? String) ?? "") ?? (alert[LuLu.Key.endpointPort] as? Int ?? 0)

        // Numele de gazdă e opțional: motorul îl pune doar când l-a putut
        // rezolva. Fără el rămâne adresa brută — mai puțin prietenos, dar
        // onest; o gazdă inventată ar fi mai rea decât un IP.
        let host = alert[LuLu.Key.hostName] as? String
        self.remoteHost = (host?.isEmpty == false ? host! : self.remoteAddress)

        // `signingInfo` e dicționarul motorului; îl citim tolerant, fiindcă
        // forma lui s-a schimbat între versiunile de LuLu.
        let signing = alert[LuLu.Key.signingInfo] as? [AnyHashable: Any]
        self.bundleID = signing?[LuLu.Key.signingID] as? String ?? signing?["teamID"] as? String
        let signer = (signing?[LuLu.Key.signer] as? Int) ?? LuLu.Signer.none
        self.isAppleSigned = (signer == LuLu.Signer.apple)
        self.isNotarized = (signer == LuLu.Signer.appStore || signer == LuLu.Signer.devID)
        self.arrivedAt = Date()
    }

    var processName: String { (path as NSString).lastPathComponent }

    var risk: RiskLevel {
        if isAppleSigned { return .safe }
        if isNotarized { return .known }
        return .unknown
    }

    var friendlyName: String {
        ProcessCatalog.shared.friendlyName(processName: processName, bundleID: bundleID, displayName: displayName)
    }

    var friendlyDetail: String {
        ProcessCatalog.shared.detail(processName: processName, bundleID: bundleID)
            ?? "Acest program vrea să trimită sau să primească date pe internet."
    }

    /// Portul, tradus acolo unde traducerea chiar ajută. Restul rămân
    /// numere — mai bine un număr onest decât o etichetă inventată.
    var portDescription: String {
        switch remotePort {
        case 80: return "web (HTTP, nesecurizat)"
        case 443: return "web securizat (HTTPS)"
        case 53: return "căutare adrese (DNS)"
        case 22: return "terminal la distanță (SSH)"
        case 25, 465, 587: return "trimitere e-mail"
        case 993, 995: return "citire e-mail"
        default: return "port \(remotePort)"
        }
    }
}

/// Decizia utilizatorului, trimisă înapoi motorului.
struct AlertVerdict {
    let request: ConnectionRequest
    let action: RuleAction
    /// `false` = doar de data asta; `true` = scrie o regulă permanentă.
    let remember: Bool
    let origin: RuleOrigin
}
