import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Ce se editează: o regulă nouă (eventual pre-completată cu un proces) sau
/// una existentă. Salvarea unei reguli existente = ștergere + adăugare.
struct RuleDraft: Identifiable {
    enum AddressKind: Int, CaseIterable, Identifiable {
        case host = 0, regex = 1, cidr = 2
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .host: return L("Domeniu sau adresă")
            case .regex: return L("Expresie regulată")
            case .cidr: return L("Interval de adrese (CIDR)")
            }
        }
    }

    let id = UUID()
    var editing: FirewallRule?
    var path: String = ""
    var isGlobal = false
    var action: RuleAction = .allow
    var anyDestination = true
    var address = ""
    var addressKind: AddressKind = .host
    var port = ""

    init(editing rule: FirewallRule? = nil, path: String = "") {
        editing = rule
        self.path = path
        guard let rule else { return }
        self.path = rule.isGlobal ? "" : rule.enginePath
        isGlobal = rule.isGlobal
        action = rule.action
        anyDestination = rule.endpointAddr == "*"
        address = rule.endpointAddr == "*" ? "" : rule.endpointAddr
        addressKind = AddressKind(rawValue: rule.endpointType) ?? .host
        port = rule.endpointPort == "*" ? "" : rule.endpointPort
    }

    /// Motivul pentru care nu se poate salva, sau nil.
    var problem: String? {
        if !isGlobal {
            if path.isEmpty { return L("Alege procesul sau bifează „Toate procesele”.") }
            if !FileManager.default.fileExists(atPath: path) { return L("Nu există niciun fișier la această cale.") }
        }
        if !anyDestination {
            let value = address.trimmingCharacters(in: .whitespaces)
            if value.isEmpty { return L("Scrie destinația sau bifează „Orice destinație”.") }
            switch addressKind {
            case .regex where (try? NSRegularExpression(pattern: value)) == nil:
                return L("Expresia regulată nu e validă.")
            case .cidr where !Self.isCIDR(value):
                return L("Intervalul trebuie să arate ca 10.0.0.0/8.")
            default: break
            }
        }
        if !port.isEmpty, !(Int(port).map { (1...65535).contains($0) } ?? false) {
            return L("Portul trebuie să fie un număr între 1 și 65535.")
        }
        return nil
    }

    static func isCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/")
        guard parts.count == 2, let bits = Int(parts[1]) else { return false }
        let octets = parts[0].split(separator: ".")
        if octets.count == 4 {
            return (0...32).contains(bits) && octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        }
        return parts[0].contains(":") && (0...128).contains(bits)
    }

    var engineInfo: [String: Any] {
        var info: [String: Any] = [
            LuLu.Key.path: isGlobal ? "*" : path,
            LuLu.Key.action: action.rawValue,
            LuLu.Key.type: LuLu.RuleType.user,
            LuLu.Key.duration: LuLu.Duration.always,
            LuLu.Key.endpointAddr: anyDestination ? "*" : address.trimmingCharacters(in: .whitespaces),
            LuLu.Key.endpointPort: port.isEmpty ? "*" : port,
        ]
        if !anyDestination, addressKind != .host { info[LuLu.Key.endpointAddrIsRegex] = addressKind.rawValue }
        if let proto = editing?.proto { info[LuLu.Key.protocol] = proto }
        return info
    }
}

struct RuleEditorView: View {
    @State var draft: RuleDraft
    let onSave: (RuleDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section(L("Proces")) {
                    Toggle(L("Toate procesele (regulă globală)"), isOn: $draft.isGlobal)
                    if !draft.isGlobal {
                        HStack {
                            TextField(L("Calea executabilului"), text: $draft.path)
                                .textFieldStyle(.roundedBorder)
                            Button(L("Alege…")) { choosePath() }
                        }
                        if !draft.path.isEmpty {
                            Label(draft.path, systemImage: "app")
                                .labelStyle(PathLabelStyle(path: draft.path))
                        }
                    }
                }
                Section(L("Acțiune")) {
                    Picker(L("Acțiune"), selection: $draft.action) {
                        Text(L("Permite")).tag(RuleAction.allow)
                        Text(L("Blochează")).tag(RuleAction.block)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section(L("Destinație")) {
                    Toggle(L("Orice destinație"), isOn: $draft.anyDestination)
                    if !draft.anyDestination {
                        Picker(L("Tip"), selection: $draft.addressKind) {
                            ForEach(RuleDraft.AddressKind.allCases) { Text($0.title).tag($0) }
                        }
                        TextField(L("ex. api.github.com, 1.2.3.4, 10.0.0.0/8"), text: $draft.address)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField(L("Port (gol = orice port)"), text: $draft.port)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let problem = draft.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
                Spacer()
                Button(L("Anulează"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Salvează")) {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.problem != nil)
            }
            .padding()
        }
        .frame(minWidth: 460, idealWidth: 540, maxWidth: .infinity, minHeight: 420, idealHeight: 500, maxHeight: .infinity)
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application, .unixExecutable, .executable, .shellScript, .item]
        panel.message = L("Alege aplicația sau executabilul pentru care se aplică regula")
        if panel.runModal() == .OK, let url = panel.url { draft.path = url.path }
    }
}

/// Pictograma reală a fișierului lângă cale.
private struct PathLabelStyle: LabelStyle {
    let path: String
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIcons.icon(forPath: path))
                .resizable()
                .frame(width: 20, height: 20)
            configuration.title
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
