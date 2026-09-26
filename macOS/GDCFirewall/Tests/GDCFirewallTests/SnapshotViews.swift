import SwiftUI
@testable import GDCFirewall

/// Ce se capturează: fiecare destinație din Setări, conținutul meniului și
/// toate formele iconului din bara de meniu.
@MainActor
enum SnapshotViews {
    static func settings() -> [(String, AnyView)] {
        [
            ("1-general", AnyView(GeneralSettings().gdcTextScaleRoot())),
            ("2-protectie", AnyView(ProtectionSettings().gdcTextScaleRoot())),
            ("3-actualizari", AnyView(UpdateSettings().gdcTextScaleRoot())),
            ("4-diagnostic", AnyView(DiagnosticSettings().gdcTextScaleRoot())),
            ("5-avansat", AnyView(AdvancedSettings(extensionIdentifier: "dev.gordas.GDCFirewall.extension").gdcTextScaleRoot())),
        ]
    }

    /// Harnaș offscreen; nu este o captură a NSMenu/MenuBarExtra real.
    static func menuHarness() -> AnyView? {
        let states: [MenuBarStatus] = [.protected, .needsApproval, .activating, .reconnecting, .filterOff,
                                       .updating, .rebootRequired, .failed("exemplu"), .stopped]
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, status in
                HStack(spacing: 10) {
                    Image(systemName: status.symbol).frame(width: 22)
                    Text(status.text).font(.callout)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) { MenuBarContent() }
        }
        .padding(14))
    }
}
