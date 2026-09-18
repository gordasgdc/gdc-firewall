import SwiftUI

/// Tabloul de bord al regulilor. Categoriile nu sunt filtre peste o listă
/// plată — sunt răspunsul la întrebarea pe care și-o pune omul când
/// deschide fereastra: „ce las să iasă, ce face sistemul singur, ce am oprit”.
struct RulesManagerView: View {
    @ObservedObject private var bridge = DaemonBridge.shared
    @ObservedObject private var autoPilot = AutoPilot.shared

    @State private var selection: RuleCategory = .verifiedApps
    @State private var search = ""

    var body: some View {
        HSplitView {
            sidebar
            content
        }
        .frame(minWidth: 860, minHeight: 540)
        .background(VisualEffectView())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GDC Firewall")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ForEach(RuleCategory.allCases) { category in
                categoryRow(category)
            }

            Spacer()

            connectionStatus
        }
        .frame(minWidth: 210, idealWidth: 230, maxWidth: 300)
        .background(VisualEffectView(material: .sidebar))
    }

    private func categoryRow(_ category: RuleCategory) -> some View {
        Button {
            selection = category
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .frame(width: 18)
                Text(category.title)
                Spacer()
                Text("\(rules(in: category).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selection == category ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bridge.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(bridge.isConnected ? L("Protecție activă") : L("Motor oprit"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    // MARK: - Conținut

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)

            if visibleRules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleRules) { rule in
                            RuleRow(rule: rule) { action in
                                bridge.setAction(action, for: rule)
                            } onDelete: {
                                bridge.delete(rule)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(selection.title)
                .font(.title3.weight(.semibold))

            Spacer()

            TextField(L("Caută"), text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            Button {
                bridge.reloadRules()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L("Reîncarcă regulile din motor"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: selection.systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyMessage: String {
        switch selection {
        case .verifiedApps: return L("Nicio aplicație aprobată încă.\nPrima dată când un program cere internet, te întreb.")
        case .systemServices: return L("Niciun serviciu de sistem în listă.")
        case .blocked: return L("N-ai blocat nimic până acum.")
        }
    }

    // MARK: - Date

    private func rules(in category: RuleCategory) -> [FirewallRule] {
        bridge.rules.filter { $0.category == category }
    }

    private var visibleRules: [FirewallRule] {
        let base = rules(in: selection)
        guard !search.isEmpty else { return base.sorted { $0.friendlyName < $1.friendlyName } }
        let needle = search.lowercased()
        return base
            .filter { $0.friendlyName.lowercased().contains(needle) || $0.processName.lowercased().contains(needle) }
            .sorted { $0.friendlyName < $1.friendlyName }
    }
}
