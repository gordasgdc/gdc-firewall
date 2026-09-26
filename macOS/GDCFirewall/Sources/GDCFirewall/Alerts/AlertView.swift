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
        .gdcTextScaleRoot()
        .gdcWindowSurface()
    }

    // MARK: - Antet

    private var header: some View {
        VStack(spacing: 14) {
            RiskBadge(risk: risk)

            // Ce se întâmplă acum, într-o propoziție.
            VStack(spacing: GDCStyle.Spacing.xs) {
                Text(request.friendlyName)
                    .gdcFont(.title)
                    .multilineTextAlignment(.center)
                Text(L("vrea să se conecteze la internet"))
                    .gdcFont(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // Faptul observat (cine a semnat) — nu un verdict.
            Text(risk.identity)
                .gdcFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(risk.tone.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(risk.tint.opacity(0.14), in: Capsule())
                .accessibilityLabel(L("Semnătură: %@", risk.identity))
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
            row(icon: risk.systemImage, title: risk.assessment, text: risk.explanation)

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
                    .gdcFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func row(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .gdcFont(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).gdcFont(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Text(text).gdcFont(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func technical(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key).gdcFont(.caption2).foregroundStyle(.secondary).frame(minWidth: 78, alignment: .leading)
            Text(value).gdcFont(.mono).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Butoane

    private var actions: some View {
        VStack(spacing: 12) {
            Toggle(L("Ține minte alegerea pentru această aplicație"), isOn: $remember)
                .gdcFont(.caption)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    send(.block)
                } label: {
                    Text(L("Blochează")).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(risk.defaultsToAllow ? .cancelAction : .defaultAction)
                .accessibilityHint(L("Conexiunea nu va fi permisă."))

                Button {
                    send(.allow)
                } label: {
                    Text(L("Permite")).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(risk.defaultsToAllow ? .defaultAction : .cancelAction)
                .accessibilityHint(L("Conexiunea va fi permisă."))
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            // Recomandarea rămâne text, nu un buton separat: trei butoane
            // într-o alertă de securitate garantează clicul greșit.
            Label {
                Text(risk.recommendation).foregroundStyle(risk.tone.foreground)
            } icon: {
                Image(systemName: "lightbulb").foregroundStyle(risk.tint)
            }
            .gdcFont(.caption)
            .fontWeight(.medium)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func send(_ action: RuleAction) {
        onVerdict(AlertVerdict(request: request, action: action, remember: remember, origin: .user))
    }
}
