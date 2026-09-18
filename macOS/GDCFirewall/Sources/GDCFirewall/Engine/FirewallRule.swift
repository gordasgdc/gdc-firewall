import Foundation

/// Acțiunea unei reguli. Valorile brute corespund 1:1 constantelor
/// `RULE_STATE_*` din motorul LuLu — modelul GDC le traduce, nu le redefinește.
enum RuleAction: Int, Codable {
    // Valorile sunt RULE_STATE_BLOCK / RULE_STATE_ALLOW (consts.h:87-90).
    case block = 0
    case allow = 1

    var label: String { self == .allow ? L("Permis") : L("Blocat") }
}

/// Cine a hotărât un verdict dat dintr-o alertă (nu o proprietate a regulii
/// din motor — aceea e `RuleKind`).
enum RuleOrigin: Int, Codable {
    case user = 0        // utilizatorul a răspuns la o alertă
    case autoPilot = 1   // Modul Silențios a aprobat automat un proces Apple
    case baseline = 2    // regulă de bază, instalată odată cu aplicația

    var label: String {
        switch self {
        case .user: return L("Decizia ta")
        case .autoPilot: return L("Aprobare inteligentă")
        case .baseline: return L("Regulă de bază")
        }
    }
}

/// Tipul regulii în motor (consts.h:378-384, `RULE_TYPE_*`) — adică cine a
/// creat-o. Folosit ca „Owner” în inspector.
enum RuleKind: Int {
    case engineDefault = 0
    case apple = 1
    case baseline = 2
    case user = 3
    /// Creată automat când nu era nicio interfață conectată care să întrebe:
    /// conexiunea a fost permisă fără decizia utilizatorului. Echivalentul
    /// regulilor „Unapproved” din Little Snitch.
    case passive = 4
    case recent = 5

    var ownerLabel: String {
        switch self {
        case .user: return L("Tu")
        case .apple: return L("Sistem (Apple)")
        case .engineDefault: return L("Motor (implicită)")
        case .baseline: return L("Motor (de bază)")
        case .passive: return L("Automată, neaprobată")
        case .recent: return L("Motor (recentă)")
        }
    }
}

/// Grupurile de reguli din bara laterală. Clasificarea se face din semnătura
/// și calea binarului — motorul nu are noțiunea de grup.
enum RuleGroup: String, CaseIterable, Identifiable {
    case iCloud
    case macOSServices
    case appleApps
    case thirdParty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return L("Servicii iCloud")
        case .macOSServices: return L("Servicii macOS")
        case .appleApps: return L("Aplicații Apple")
        case .thirdParty: return L("Aplicații terțe")
        }
    }

    var systemImage: String {
        switch self {
        case .iCloud: return "icloud"
        case .macOSServices: return "gearshape.2"
        case .appleApps: return "apple.logo"
        case .thirdParty: return "square.grid.2x2"
        }
    }

    /// Procesele care vorbesc cu iCloud, după numele binarului.
    private static let iCloudProcesses: Set<String> = [
        "cloudd", "bird", "CloudKeychainProxy", "cloudphotod", "photolibraryd",
        "iCloudNotificationAgent", "itunescloudd", "cloudpaird", "fileproviderd",
        "findmydeviced", "icloudmailagent", "keychainsharingmessagingd",
    ]

    static func classify(path: String, signingID: String?, isAppleSigned: Bool) -> RuleGroup {
        let process = (path as NSString).lastPathComponent
        if iCloudProcesses.contains(process) || signingID?.hasPrefix("com.apple.cloud") == true { return .iCloud }
        guard isAppleSigned else { return .thirdParty }
        // O aplicație Apple are un pachet .app în afara /System (Safari, Pages,
        // Xcode); tot restul semnat de Apple e un serviciu al sistemului.
        if path.contains(".app/") && !path.hasPrefix("/System/Library/") && !path.hasPrefix("/usr/") {
            return .appleApps
        }
        return .macOSServices
    }
}

/// O regulă, așa cum o vede interfața GDC — toate câmpurile pe care motorul
/// le păstrează (Shared/Rule.h), citite prin KVC.
///
/// Ce NU există în motor și deci nici aici: prioritate, contor de utilizare,
/// ultimul acces, cale „via”, checksum. Nu se inventează.
struct FirewallRule: Identifiable, Hashable {
    let id: String
    let uuid: String
    /// Cheia din dicționarul de reguli al motorului — de regulă
    /// „semnătură:autoritate”, nu calea. `deleteRule`/`toggleRule` o cer.
    let engineKey: String
    /// Calea binarului (sau `*` pentru o regulă globală).
    let enginePath: String
    let engineName: String?
    let endpointAddr: String
    let endpointHost: String?
    let endpointPort: String
    /// `EndpointType`: 0 exact, 1 regex, 2 CIDR, 3 glob.
    let endpointType: Int
    let proto: Int?
    let kind: RuleKind
    var action: RuleAction
    var isDisabled: Bool
    let creation: Date?
    let expiration: Date?
    /// Setat doar la regulile valabile cât rulează un anumit proces.
    let pid: Int?
    let scope: Int?

    let bundleID: String?
    let teamID: String?
    let signer: Int
    let authorities: [String]
    /// `signatureStatus` din motor: 0 = semnătură validă când a fost creată regula.
    let signatureStatus: Int?

    var friendlyName: String

    // MARK: - Derivate

    var processName: String { (enginePath as NSString).lastPathComponent }
    var isGlobal: Bool { enginePath == "*" }
    var isDirectory: Bool { enginePath.hasSuffix("/*") }
    var isAppleSigned: Bool { kind == .apple || signer == LuLu.Signer.apple }
    var isNotarized: Bool { signer == LuLu.Signer.appStore || signer == LuLu.Signer.devID }
    var isUnapproved: Bool { kind == .passive }
    var isTemporary: Bool { pid != nil || expiration != nil }
    var isExpired: Bool { expiration.map { $0 < Date() } ?? false }
    var isAnyDestination: Bool { endpointAddr == "*" && endpointPort == "*" }
    var hasIdentity: Bool { bundleID != nil || teamID != nil }

    var group: RuleGroup {
        RuleGroup.classify(path: enginePath, signingID: bundleID, isAppleSigned: isAppleSigned)
    }

    /// `false` = executabilul la care se referă regula nu mai există: regula
    /// probabil nu mai are niciun efect.
    var executableExists: Bool {
        if isGlobal { return true }
        let path = isDirectory ? String(enginePath.dropLast(2)) : enginePath
        return FileManager.default.fileExists(atPath: path)
    }

    /// Locul de pe disc de unde vine pictograma și unde duce „Arată în Finder”.
    var fileURL: URL? {
        guard !isGlobal else { return nil }
        let path = isDirectory ? String(enginePath.dropLast(2)) : enginePath
        return URL(fileURLWithPath: path)
    }

    /// Destinația, pe scurt: „orice destinație”, „api.github.com:443”.
    var targetDescription: String {
        let host = endpointHost ?? endpointAddr
        let kindNote: String
        switch endpointType {
        case LuLu.EndpointType.regex: kindNote = " " + L("(expresie)")
        case LuLu.EndpointType.cidr: kindNote = " " + L("(interval de adrese)")
        default: kindNote = ""
        }
        switch (endpointAddr, endpointPort) {
        case ("*", "*"): return L("orice destinație")
        case ("*", let port): return L("orice destinație, port %@", port)
        case (_, "*"): return host + kindNote
        default: return "\(host):\(endpointPort)" + kindNote
        }
    }

    /// Fraza din antetul inspectorului: „permite orice conexiune de ieșire”.
    var summary: String {
        if isAnyDestination {
            return action == .allow ? L("permite orice conexiune de ieșire") : L("blochează orice conexiune de ieșire")
        }
        return action == .allow
            ? L("permite conexiunile de ieșire către %@", targetDescription)
            : L("blochează conexiunile de ieșire către %@", targetDescription)
    }

    // MARK: - Construcție

    /// Construiește regula dintr-un obiect `Rule` al motorului, citit prin
    /// KVC. Stratul GDC nu redeclară clasa motorului: dacă un câmp dispare
    /// acolo, aici primim `nil` și sărim regula, în loc să crăpăm.
    init?(engineRule object: AnyObject, path: String, key: String) {
        guard let uuid = object.value(forKey: "uuid") as? String else { return nil }
        let signing = object.value(forKey: "csInfo") as? [AnyHashable: Any]

        self.id = uuid
        self.uuid = uuid
        self.engineKey = key
        self.enginePath = path
        self.engineName = object.value(forKey: "name") as? String
        self.endpointAddr = object.value(forKey: "endpointAddr") as? String ?? "*"
        self.endpointHost = object.value(forKey: "endpointHost") as? String
        self.endpointPort = object.value(forKey: "endpointPort") as? String ?? "*"
        self.endpointType = (object.value(forKey: "isEndpointAddrRegex") as? NSNumber)?.intValue ?? 0
        self.proto = (object.value(forKey: "protocol") as? NSNumber)?.intValue
        let type = (object.value(forKey: "type") as? NSNumber)?.intValue ?? LuLu.RuleType.default
        self.kind = RuleKind(rawValue: type) ?? .engineDefault
        self.action = RuleAction(rawValue: (object.value(forKey: "action") as? NSNumber)?.intValue ?? LuLu.RuleState.block) ?? .block
        self.isDisabled = (object.value(forKey: "isDisabled") as? NSNumber)?.boolValue ?? false
        self.creation = object.value(forKey: "creation") as? Date
        self.expiration = object.value(forKey: "expiration") as? Date
        self.pid = (object.value(forKey: "pid") as? NSNumber)?.intValue
        self.scope = (object.value(forKey: "scope") as? NSNumber)?.intValue

        self.bundleID = signing?[LuLu.Key.signingID] as? String
        self.signer = (signing?[LuLu.Key.signer] as? Int) ?? LuLu.Signer.none
        self.authorities = signing?["signatureAuthorities"] as? [String] ?? []
        self.teamID = Self.teamID(from: self.authorities)
        self.signatureStatus = (signing?["signatureStatus"] as? NSNumber)?.intValue

        self.friendlyName = path == "*"
            ? L("Toate procesele")
            : ProcessCatalog.shared.friendlyName(
                processName: (path as NSString).lastPathComponent,
                bundleID: signing?[LuLu.Key.signingID] as? String,
                displayName: object.value(forKey: "name") as? String)
    }

    /// Motorul nu păstrează Team ID-ul separat: e în numele certificatului
    /// frunză, „Developer ID Application: Nume (TEAMID)”. Semnăturile Apple
    /// apar ca „APPLE”, ca în Little Snitch (ex. APPLE/com.apple.iCal).
    static func teamID(from authorities: [String]) -> String? {
        guard let leaf = authorities.first else { return nil }
        if leaf == "Software Signing" || leaf.hasPrefix("Apple ") { return "APPLE" }
        guard let open = leaf.lastIndex(of: "("), let close = leaf.lastIndex(of: ")"), open < close else { return nil }
        return String(leaf[leaf.index(after: open)..<close])
    }

    // MARK: - Pentru motor

    /// Dicționarul pentru `addRule`, pornind de la această regulă — baza
    /// pentru Duplicare, Editare, Globală și Repararea căii.
    func engineInfo(path: String? = nil, action: RuleAction? = nil, addr: String? = nil,
                    port: String? = nil, endpointType: Int? = nil) -> [String: Any] {
        var info: [String: Any] = [
            LuLu.Key.path: path ?? enginePath,
            LuLu.Key.action: (action ?? self.action).rawValue,
            LuLu.Key.type: LuLu.RuleType.user,
            LuLu.Key.duration: LuLu.Duration.always,
            LuLu.Key.endpointAddr: addr ?? endpointAddr,
            LuLu.Key.endpointPort: port ?? endpointPort,
        ]
        let type = endpointType ?? self.endpointType
        if type != LuLu.EndpointType.exact { info[LuLu.Key.endpointAddrIsRegex] = type }
        if let proto { info[LuLu.Key.protocol] = proto }
        return info
    }
}
