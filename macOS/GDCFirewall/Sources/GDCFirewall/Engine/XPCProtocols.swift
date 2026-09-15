import Foundation

/// Protocolul daemon-ului, copiat semnătură cu semnătură din
/// `Engine/LuLu/LuLu/Shared/XPCDaemonProto.h` (v4.5.1). O singură literă
/// diferită aici înseamnă `NSXPCConnection` care aruncă la runtime, nu
/// eroare de compilare — de aia fișierul ăsta se verifică manual la fiecare
/// urcare de tag al motorului.
@objc protocol XPCDaemonProtocol {
    func checkIn(_ reply: @escaping (Bool) -> Void)
    func getPreferences(_ reply: @escaping ([AnyHashable: Any]) -> Void)
    func updatePreferences(_ preferences: [AnyHashable: Any], reply: @escaping ([AnyHashable: Any]) -> Void)

    /// Atenție: întoarce `NSData` — o arhivă `NSKeyedArchiver` de obiecte
    /// `Rule` (clasă Objective-C a motorului), NU un array de dicționare.
    func getRules(_ reply: @escaping (Data) -> Void)

    func addRule(_ info: [AnyHashable: Any])
    func toggleRule(_ key: String, rule uuid: String, state: NSNumber)
    func deleteRule(_ key: String, rule uuid: String)
    func uninstall(_ reply: @escaping (Bool) -> Void)
}

/// Protocolul pe care îl exportăm NOI. Daemon-ul ne apelează pe noi —
/// alertele nu se cer, vin. `reply` trebuie apelat exact o dată; dacă
/// blocul se pierde, conexiunea rămâne blocată și extensia ține conexiunea
/// de rețea în așteptare.
@objc protocol XPCUserProtocol {
    func rulesChanged()
    func alertShow(_ alert: [AnyHashable: Any], reply: @escaping ([AnyHashable: Any]) -> Void)
}
