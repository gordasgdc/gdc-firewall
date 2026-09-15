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

    /// consts.h:81 — `DAEMON_MACH_SERVICE`.
    ///
    /// Prefixul e Team ID-ul celui care semnează daemon-ul, nu un text
    /// oarecare: macOS refuză conexiunea dacă aplicația nu e semnată cu
    /// ACELAȘI Team ID. De aceea GDC Firewall se construiește din sursa
    /// motorului, cu Team ID-ul GDC, nu ca aplicație separată lângă un LuLu
    /// oficial descărcat de pe obdev.at — vezi CLAUDE.md, Partea 2.
    static let teamID = "VBG97UB4TA"
    static var daemonMachService: String { "\(teamID).com.objective-see.lulu" }

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
    }
}
