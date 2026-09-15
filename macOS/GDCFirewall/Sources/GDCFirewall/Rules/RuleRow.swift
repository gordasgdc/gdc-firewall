import SwiftUI

/// Un rând din Rules Manager: pictograma aplicației, numele intuitiv,
/// insigna de conexiune, comutatorul. Pictograma vine din Finder
/// (`NSWorkspace.icon(forFile:)`) — dacă binarul nu mai există pe disc,
/// rămâne o pictogramă generică, nu un spațiu gol.
struct RuleRow: View {
    let rule: FirewallRule
    let onChange: (RuleAction) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var risk: RiskLevel {
        if rule.isAppleSigned { return .safe }
        return rule.isNotarized ? .known : .unknown
    }

    var body: some View {
        GlassCard(cornerRadius: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: rule.enginePath))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.friendlyName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        RiskDot(risk: risk)
                        Text(rule.processName)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                badge

                Toggle("", isOn: Binding(
                    get: { rule.action == .allow },
                    set: { onChange($0 ? .allow : .block) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(rule.action == .allow ? "Are acces la internet" : "Accesul e blocat")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0)
                .help("Șterge regula — te voi întreba din nou data viitoare")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onHover { isHovered = $0 }
    }

    /// Insigna de conexiune: câte conexiuni și când a fost ultima. Când
    /// n-avem date, nu desenăm o insignă goală.
    @ViewBuilder private var badge: some View {
        if rule.connectionCount > 0 {
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(rule.connectionCount) conexiuni")
                    .font(.caption2.monospacedDigit())
                if let last = rule.lastConnection {
                    Text(last, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        } else {
            Text(rule.origin.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
