import SwiftUI

/// Fereastra de alertă, redesenată de la zero pentru cineva care nu știe
/// ce e un proces. Ierarhia e deliberat inversă față de firewall-urile
/// clasice: întâi CINE și CE vrea (în română), apoi recomandarea, și abia
/// la final detaliile tehnice — ascunse într-un disclosure, nu eliminate.
struct AlertView: View {
    let request: ConnectionRequest
    let onVerdict: (AlertVerdict) -> Void

    @State private var remember = true
    @State private var showTechnical = false

    private var risk: RiskLevel { request.risk }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            details
            Divider().opacity(0.4)
            actions
        }
        .frame(minWidth: 400, idealWidth: 440, maxWidth: .infinity)
        .background(VisualEffectView())
    }

    // MARK: - Antet

    private var header: some View {
        VStack(spacing: 14) {
            RiskBadge(risk: risk)

            Text(request.friendlyName)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(L("vrea să se conecteze la internet"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(risk.title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(risk.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(risk.tint.opacity(0.14), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .padding(.horizontal, 24)
    }

    // MARK: - Explicații

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(icon: "info.circle", title: L("Ce face"), text: request.friendlyDetail)
            row(icon: "globe", title: L("Unde se conectează"), text: "\(request.remoteHost) · \(request.portDescription)")
            row(icon: risk.systemImage, title: L("De ce te întreb"), text: risk.explanation)

            DisclosureGroup(isExpanded: $showTechnical) {
                VStack(alignment: .leading, spacing: 4) {
                    technical(L("Proces"), request.processName)
                    technical(L("Cale"), request.path)
                    if let bundleID = request.bundleID { technical(L("Identificator"), bundleID) }
                    technical(L("Adresă"), "\(request.remoteAddress):\(request.remotePort)")
                    technical("PID", "\(request.processID)")
                }
                .padding(.top, 8)
            } label: {
                Text(L("Detalii tehnice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func row(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func technical(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key).font(.caption2).foregroundStyle(.tertiary).frame(width: 78, alignment: .leading)
            Text(value).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
        }
    }

    // MARK: - Butoane

    private var actions: some View {
        VStack(spacing: 12) {
            Toggle(L("Ține minte alegerea pentru această aplicație"), isOn: $remember)
                .font(.caption)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    send(.block)
                } label: {
                    Text(L("Blochează")).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(risk.defaultsToAllow ? .cancelAction : .defaultAction)

                Button {
                    send(.allow)
                } label: {
                    Text(L("Permite")).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(risk.defaultsToAllow ? .defaultAction : .cancelAction)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            // Recomandarea rămâne text, nu un buton separat: trei butoane
            // într-o alertă de securitate garantează clicul greșit.
            Label(risk.recommendation, systemImage: "lightbulb")
                .font(.caption.weight(.medium))
                .foregroundStyle(risk.tint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func send(_ action: RuleAction) {
        onVerdict(AlertVerdict(request: request, action: action, remember: remember, origin: .user))
    }
}
