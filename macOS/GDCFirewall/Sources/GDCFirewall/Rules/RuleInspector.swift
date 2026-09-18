import AppKit
import SwiftUI

/// Panoul lateral de detalii al unei reguli.
///
/// Arată doar ce știe motorul. Câmpurile Little Snitch fără echivalent în
/// LuLu — prioritate, contor de utilizare, ultimul acces, cale „via”,
/// checksum — lipsesc intenționat, în loc să apară mereu „—”.
struct RuleInspector: View {
    let rules: [FirewallRule]
    let onEdit: (FirewallRule) -> Void
    let onRepair: (FirewallRule) -> Void
    @ObservedObject private var identity = IdentityChecker.shared
    @ObservedObject private var bridge = DaemonBridge.shared

    var body: some View {
        if rules.count == 1, let rule = rules.first {
            detail(rule)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(rules.isEmpty ? L("Alege o regulă ca să-i vezi detaliile.") : L("%d reguli selectate", rules.count))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detail(_ rule: FirewallRule) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(rule)
                    banners(rule)
                    section(L("Cale")) {
                        pathRow(rule)
                    }
                    section(L("Identificare")) {
                        field(L("ID cod"), rule.bundleID ?? L("nesemnat"))
                        field(L("Team ID"), rule.teamID ?? "—")
                        if let signer = rule.authorities.first { field(L("Semnat de"), signer) }
                        identityCheck(rule)
                    }
                    section(L("Regulă")) {
                        field(L("Acțiune"), rule.action.label)
                        field(L("Destinație"), rule.targetDescription)
                        field(L("Protocol"), protocolName(rule.proto))
                        field(L("Proprietar"), rule.kind.ownerLabel)
                        field(L("Creată"), rule.creation.map(Self.fullDate) ?? "—")
                        if let expiration = rule.expiration { field(L("Expiră"), Self.fullDate(expiration)) }
                        if rule.pid != nil { field(L("Valabilă"), L("cât rulează procesul")) }
                        field(L("Stare"), rule.isDisabled ? L("dezactivată") : L("activă"))
                    }
                    origin(rule)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button { reveal(rule) } label: { Label(L("Arată în Finder"), systemImage: "folder") }
                    .disabled(!rule.executableExists || rule.isGlobal)
                Spacer()
                Button { onEdit(rule) } label: { Label(L("Editează"), systemImage: "pencil") }
                Button(role: .destructive) { bridge.delete(rule) } label: { Label(L("Șterge"), systemImage: "trash") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    // MARK: - Părți

    private func header(_ rule: FirewallRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: AppIcons.icon(for: rule))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.friendlyName).font(.title3.weight(.semibold))
                Text(rule.processName).font(.caption).foregroundStyle(.secondary)
                Text(rule.summary)
                    .font(.callout)
                    .foregroundStyle(rule.action.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func banners(_ rule: FirewallRule) -> some View {
        if !rule.executableExists {
            banner(L("Regula probabil nu mai are efect: executabilul la care se referă a fost șters, mutat sau redenumit."),
                   symbol: "exclamationmark.triangle.fill") {
                Button(L("Repară calea…")) { onRepair(rule) }
            }
        }
        if rule.isUnapproved {
            banner(L("Creată automat, fără decizia ta."), symbol: "questionmark.circle.fill") {
                Button(L("Aprobă")) { bridge.approve([rule]) }
            }
        }
        if rule.isExpired {
            banner(L("Regula a expirat și nu mai are efect."), symbol: "calendar.badge.exclamationmark") { EmptyView() }
        }
        if let status = rule.signatureStatus, status != 0 {
            banner(L("Semnătura programului era invalidă când a fost creată regula (cod %d).", status),
                   symbol: "xmark.seal.fill") { EmptyView() }
        }
    }

    private func banner<Action: View>(_ text: String, symbol: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func pathRow(_ rule: FirewallRule) -> some View {
        HStack(alignment: .top) {
            Text(rule.isGlobal ? L("Toate procesele") : rule.enginePath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if rule.executableExists && !rule.isGlobal {
                Button { reveal(rule) } label: { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(.borderless)
                    .help(L("Arată în Finder"))
            }
        }
    }

    @ViewBuilder
    private func identityCheck(_ rule: FirewallRule) -> some View {
        if rule.hasIdentity, !rule.isGlobal, let now = identity.current[rule.enginePath] {
            if IdentityChecker.matches(rule: rule, current: now) {
                Label(L("Semnătura de pe disc corespunde regulii."), systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(L("Semnătura de pe disc diferă: acum %@ / %@.", now.codeID ?? "—", now.teamID ?? "—"),
                      systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
            }
        } else if !rule.hasIdentity && !rule.isGlobal {
            Text(L("Program nesemnat: motorul îl recunoaște doar după cale."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func origin(_ rule: FirewallRule) -> some View {
        let date = rule.creation.map(Self.fullDate) ?? "—"
        let text: String
        switch rule.kind {
        case .user:
            text = L("Creată de tine pe %@, dintr-o alertă, din fereastra Reguli sau printr-un import.", date)
        case .passive:
            text = L("Pe %@, %@ a încercat să se conecteze cât interfața GDC nu era pornită. Motorul a permis conexiunea și a creat automat această regulă.", date, rule.friendlyName)
        case .apple:
            text = L("Regulă a sistemului: %@ e semnat de Apple și face parte din macOS.", rule.friendlyName)
        case .engineDefault, .baseline, .recent:
            text = L("Regulă a motorului de filtrare, necesară funcționării macOS.")
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func field(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, idealWidth: 90, maxWidth: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func protocolName(_ proto: Int?) -> String {
        switch proto {
        case Int(IPPROTO_TCP): return "TCP"
        case Int(IPPROTO_UDP): return "UDP"
        default: return L("oricare")
        }
    }

    private func reveal(_ rule: FirewallRule) {
        guard let url = rule.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppIcons.bundlePath(containing: url.path) ?? url.path)])
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Lang.current.rawValue)
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

extension RuleAction {
    /// Culorile de stare, definite o singură dată (Regula 37).
    var tint: Color { self == .allow ? .green : .red }
}
