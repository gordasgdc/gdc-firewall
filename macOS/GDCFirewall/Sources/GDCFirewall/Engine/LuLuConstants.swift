import Foundation

/// Constantele motorului, oglindite din `Engine/LuLu/LuLu/Shared/consts.h`
/// (tag v4.5.1). Sunt copiate, nu reinterpretate — fiecare are notat rândul
/// din care vine, ca o actualizare de motor să poată fi verificată rând cu
/// rând. `scripts/fetch-engine.sh` oprește build-ul dacă tag-ul diferă.
enum LuLu {
    /// Versiunea motorului cu care e construită ACEASTĂ aplicație.
    ///
    /// E sursa de adevăr pentru jumătatea „motor” a verificării de
    /// actualizări: serverul anunță în `update.json` versiunea minimă de
    /// motor încă susținută, iar clientul se compară cu valoarea de aici.
    /// `scripts/fetch-engine.sh` verifică la fiecare build că e identică cu
    /// tag-ul clonat — altfel aplicația ar raporta un motor pe care nu-l are.
    static let engineVersion = "4.5.1"

    /// consts.h:81 — `DAEMON_MACH_SERVICE`, cu valoarea scrisă de
    /// `scripts/integrate-engine.sh`, NU cea upstream
    /// (`VBG97UB4TA.com.objective-see.lulu`): cu aceea aplicația căuta un
    /// serviciu care nu există și rămânea pe „Motor oprit”.
    ///
    /// Prefixul e Team ID-ul celui care semnează daemon-ul: macOS refuză
    /// conexiunea dacă aplicația nu e semnată cu ACELAȘI Team ID.
    /// Literal, nu interpolat: `build_engine_app.sh` îl caută în binar și îl
    /// compară cu `NEMachServiceName` al extensiei construite.
    static let teamID = "8AR6XP8MG7"
    static let daemonMachService = "8AR6XP8MG7.dev.gordas.GDCFirewall"

    /// consts.h:87-90 — `RULE_STATE_BLOCK` / `RULE_STATE_ALLOW`.
    enum RuleState {
        static let notFound = -1
        static let block = 0
        static let allow = 1
    }

    /// consts.h:378-384 — tipul regulii.
    enum RuleType {
        static let `default` = 0
        static let apple = 1
        static let baseline = 2
        static let user = 3
    }

    /// consts.h:400-403 — cât de larg se aplică decizia.
    enum ActionScope {
        static let unselected = -1
        static let process = 0
        static let endpoint = 1
        static let processTree = 2
    }

    /// consts.h:18-23 — `RuleDurationTag`.
    enum Duration {
        static let always = 101
        static let once = 102
        static let process = 103
    }

    /// consts.h:387-388 — `RULE_TOGGLE_STATE_*`.
    enum RuleToggle {
        static let enable = 1
        static let disable = 0
    }

    /// consts.h:193-202 — preferințele de blocklist / listă de excepții.
    enum Pref {
        static let useBlockList = "useBlockList"
        static let blockList = "blockList"
    }

    /// consts.h:28-33 — `EndpointType`, cum se interpretează `endpointAddr`.
    enum EndpointType {
        static let exact = 0
        static let regex = 1
        static let cidr = 2
    }

    /// consts.h:16 — `enum Signer{None, Apple, AppStore, DevID, AdHoc}`.
    /// Fără inițializatori expliciți, deci numerotare C de la 0: Apple e 1,
    /// nu 0. `None` (0) înseamnă NESEMNAT — opusul lui „sigur”.
    enum Signer {
        static let none = 0
        static let apple = 1
        static let appStore = 2
        static let devID = 3
        static let adHoc = 4
    }

    /// Cheile dicționarelor de alertă (consts.h:320-364).
    enum Key {
        static let uuid = "uuid"
        static let path = "path"
        static let name = "name"
        static let pid = "pid"
        static let type = "type"
        static let action = "action"
        static let scope = "scope"
        static let duration = "duration"
        static let userID = "userID"
        static let endpointAddr = "endpointAddr"
        static let endpointPort = "endpointPort"
        static let hostName = "hostName"
        static let signingInfo = "signingInfo"
        static let signer = "signatureSigner"        // consts.h:330
        static let signingID = "signatureIdentifier" // consts.h:327
        static let processDeleted = "deleted"
        static let endpointAddrIsRegex = "endpointAddrIsRegex" // consts.h:344
        static let `protocol` = "protocol"                      // consts.h:359
    }
}
