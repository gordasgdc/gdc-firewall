import Foundation
@testable import GDCFirewall

/// Date sintetice comune testelor: cereri de conexiune și reguli construite
/// exact din forma dicționarelor pe care le trimite motorul.
enum Fixtures {
    static func request(
        path: String = "/Applications/Zoom.us.app/Contents/MacOS/zoom.us",
        name: String? = "zoom.us",
        signingID: String? = "us.zoom.xos",
        signer: Int = LuLu.Signer.devID,
        host: String = "zoom.us",
        port: String = "443"
    ) -> ConnectionRequest {
        var signing: [AnyHashable: Any] = [LuLu.Key.signer: signer]
        if let signingID { signing[LuLu.Key.signingID] = signingID }
        var alert: [AnyHashable: Any] = [
            LuLu.Key.uuid: UUID().uuidString,
            LuLu.Key.path: path,
            LuLu.Key.pid: 4242,
            LuLu.Key.endpointAddr: "203.0.113.7",
            LuLu.Key.endpointPort: port,
            LuLu.Key.hostName: host,
            LuLu.Key.signingInfo: signing,
        ]
        if let name { alert[LuLu.Key.name] = name }
        return ConnectionRequest(alert: alert)!
    }

    /// `FirewallRule(engineRule:)` citește prin KVC — un NSDictionary răspunde
    /// la `value(forKey:)` la fel ca obiectul `Rule` al motorului.
    static func rule(
        path: String = "/Applications/Zoom.us.app/Contents/MacOS/zoom.us",
        addr: String = "*",
        port: String = "*",
        action: RuleAction = .allow,
        kind: RuleKind = .user,
        disabled: Bool = false,
        created: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        expires: Date? = nil,
        pid: Int? = nil,
        signingID: String? = nil
    ) -> FirewallRule {
        let object = NSMutableDictionary()
        object["uuid"] = UUID().uuidString
        object["endpointAddr"] = addr
        object["endpointPort"] = port
        object["action"] = NSNumber(value: action.rawValue)
        object["type"] = NSNumber(value: kind.rawValue)
        object["isDisabled"] = NSNumber(value: disabled)
        if let created { object["creation"] = created }
        if let expires { object["expiration"] = expires }
        if let pid { object["pid"] = NSNumber(value: pid) }
        if let signingID { object["csInfo"] = [LuLu.Key.signingID: signingID, LuLu.Key.signer: LuLu.Signer.devID] }
        return FirewallRule(engineRule: object, path: path, key: path)!
    }
}
