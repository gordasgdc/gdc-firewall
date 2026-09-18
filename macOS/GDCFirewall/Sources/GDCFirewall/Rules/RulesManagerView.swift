import AppKit
import SwiftUI

/// Fereastra Reguli: bară laterală → tabel → inspector.
struct RulesManagerView: View {
    @ObservedObject private var bridge = DaemonBridge.shared
    @ObservedObject private var identity = IdentityChecker.shared
    @ObservedObject private var blocklist = BlocklistStore.shared

    @State private var sidebar: SidebarItem? = .all
    @State private var selection: Set<FirewallRule.ID> = []
    @State private var search = ""
    /// „Arată doar regulile care afectează procesul X” (meniul contextual).
    @State private var focusPath: String?
    @State private var showInspector = true
    @State private var editorDraft: RuleDraft?
    @State private var repairing: FirewallRule?
    @State private var pendingDelete: [FirewallRule] = []
    @State private var status: String?
    @State private var sortOrder = [KeyPathComparator(\FirewallRule.friendlyName, order: .forward)]

    var body: some View {
        NavigationSplitView {
            RuleSidebar(selection: $sidebar, onExport: export, onDeleteGroup: { pendingDelete = $0 })
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 380)
        } detail: {
            detail
                .inspectorCompat(isPresented: $showInspector, enabled: sidebar != .blocklist) {
                    RuleInspector(rules: selectedRules,
                                  onEdit: { editorDraft = RuleDraft(editing: $0) },
                                  onRepair: repair)
                }
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("Caută proces, cale sau destinație"))
        .toolbar { toolbar }
        .sheet(item: $editorDraft) { draft in
            RuleEditorView(draft: draft) { saved in
                if let original = saved.editing {
                    bridge.replace(original, with: saved.engineInfo)
                } else {
                    bridge.add(saved.engineInfo)
                }
            }
        }
        .confirmationDialog(L("Ștergi %d reguli?", pendingDelete.count),
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button(L("Șterge"), role: .destructive) {
                bridge.delete(pendingDelete)
                selection.subtract(pendingDelete.map(\.id))
                pendingDelete = []
            }
        } message: {
            Text(L("Data viitoare când aceste programe se conectează, vei fi întrebat din nou."))
        }
        .onAppear { identity.check(bridge.rules) }
        .onChange(of: bridge.rules) { identity.check($0) }
        .onChange(of: sidebar) { _ in
            selection = []
            focusPath = nil
        }
        .frame(minWidth: 760, idealWidth: 1100, maxWidth: .infinity, minHeight: 440, idealHeight: 680, maxHeight: .infinity)
    }

    // MARK: - Conținut

    @ViewBuilder
    private var detail: some View {
        if sidebar == .blocklist {
            BlocklistView()
        } else {
            VStack(spacing: 0) {
                listHeader
                if visibleRules.isEmpty {
                    emptyState
                } else {
                    table
                }
                if let status {
                    Divider()
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label((sidebar ?? .all).title, systemImage: (sidebar ?? .all).systemImage)
                    .font(.headline)
                Text("\(visibleRules.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let focusPath {
                    Button {
                        self.focusPath = nil
                    } label: {
                        Label(L("Doar %@", (focusPath as NSString).lastPathComponent), systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Arată din nou toate regulile"))
                }
                if sidebar == .unapproved, !visibleRules.isEmpty {
                    Button(L("Aprobă toate")) { bridge.approve(visibleRules) }
                }
                if sidebar == .expired || sidebar == .redundant, !visibleRules.isEmpty {
                    Button(L("Șterge toate")) { pendingDelete = visibleRules }
                }
            }
            if let explanation = sidebar?.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var table: some View {
        Table(visibleRules, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { rule in
                Image(nsImage: AppIcons.icon(for: rule))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .opacity(rule.isDisabled ? 0.4 : 1)
            }
            .width(26)
            TableColumn(L("Proces"), value: \.friendlyName) { rule in
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.friendlyName)
                        .strikethrough(rule.isDisabled)
                    Text(rule.isGlobal ? L("toate procesele") : rule.processName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help(rule.enginePath)
            }
            .width(min: 160, ideal: 240)
            TableColumn(L("Stare"), value: \.stateSortKey) { rule in
                RuleStateBadge(rule: rule)
            }
            .width(min: 90, ideal: 110)
            TableColumn(L("Regulă / destinație"), value: \.targetDescription) { rule in
                Text(rule.targetDescription)
                    .foregroundStyle(rule.isDisabled ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 140, ideal: 260)
            TableColumn(L("Creată"), value: \.creationSortKey) { rule in
                Text(rule.creation.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 140)
        }
        .contextMenu(forSelectionType: FirewallRule.ID.self) { ids in
            contextMenu(for: rules(with: ids))
        } primaryAction: { ids in
            if let rule = rules(with: ids).first { editorDraft = RuleDraft(editing: rule) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: (sidebar ?? .all).systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(bridge.isConnected ? L("Nicio regulă aici.") : L("Motorul nu e conectat — regulile apar după conectare."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Meniul contextual

    @ViewBuilder
    private func contextMenu(for rules: [FirewallRule]) -> some View {
        if let rule = rules.first {
            let name = rule.isGlobal ? L("toate procesele") : rule.friendlyName
            if rules.count == 1 {
                Button(L("Regulă nouă pentru „%@”", name)) {
                    editorDraft = RuleDraft(path: rule.isGlobal ? "" : rule.enginePath)
                }
                Button(L("Duplică")) { bridge.duplicate(rule) }
                Button(L("Editează regula…")) { editorDraft = RuleDraft(editing: rule) }
                if !rule.isGlobal {
                    Button(L("Transformă în regulă globală")) { bridge.makeGlobal(rule) }
                }
                Divider()
            }
            if rules.contains(where: \.isUnapproved) {
                Button(L("Aprobă")) { bridge.approve(rules) }
            }
            if rules.contains(where: \.isDisabled) {
                Button(L("Activează")) { bridge.setEnabled(true, for: rules) }
            }
            if rules.contains(where: { !$0.isDisabled }) {
                Button(L("Dezactivează")) { bridge.setEnabled(false, for: rules) }
            }
            Divider()
            Button(L("Copiază regula")) { copy(rules.map { "\($0.friendlyName) (\($0.enginePath)): \($0.summary)" }) }
            Button(L("Copiază calea procesului")) { copy(rules.map(\.enginePath)) }
            Button(L("Copiază domeniile")) { copy(rules.filter { $0.endpointAddr != "*" }.map { $0.endpointHost ?? $0.endpointAddr }) }
            Divider()
            if rules.count == 1 {
                Button(L("Arată în Finder")) {
                    if let url = rule.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppIcons.bundlePath(containing: url.path) ?? url.path)])
                    }
                }
                .disabled(!rule.executableExists || rule.isGlobal)
                if !rule.executableExists {
                    Button(L("Repară calea procesului…")) { repair(rule) }
                }
                if !rule.isGlobal {
                    Button(L("Arată doar regulile pentru „%@”", name)) {
                        sidebar = .all
                        DispatchQueue.main.async { focusPath = rule.enginePath }
                    }
                }
            }
            Button(L("Exportă…")) { export(rules, name: rules.count == 1 ? rule.friendlyName : (sidebar ?? .all).title) }
            Divider()
            Button(L("Șterge"), role: .destructive) { pendingDelete = rules }
        }
    }

    // MARK: - Bara de instrumente

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { editorDraft = RuleDraft() } label: { Label(L("Regulă nouă"), systemImage: "plus") }
                .help(L("Regulă nouă"))
            Button { AuxWindowPresenter.showSetup() } label: { Label(L("Importă…"), systemImage: "square.and.arrow.down") }
                .help(L("Importă reguli din Little Snitch sau LuLu"))
            Button { export(visibleRules, name: (sidebar ?? .all).title) } label: {
                Label(L("Exportă…"), systemImage: "square.and.arrow.up")
            }
            .help(L("Exportă regulile afișate"))
            .disabled(visibleRules.isEmpty)
            Button { bridge.reloadRules() } label: { Label(L("Reîncarcă"), systemImage: "arrow.clockwise") }
                .help(L("Reîncarcă regulile din motor"))
            Button { showInspector.toggle() } label: { Label(L("Inspector"), systemImage: "sidebar.right") }
                .help(L("Arată sau ascunde detaliile"))
        }
    }

    // MARK: - Date

    private var selectedRules: [FirewallRule] { rules(with: selection) }

    private func rules(with ids: Set<FirewallRule.ID>) -> [FirewallRule] {
        bridge.rules.filter { ids.contains($0.id) }
    }

    private var visibleRules: [FirewallRule] {
        var result = RuleAnalysis.rules(for: sidebar ?? .all, in: bridge.rules, mismatches: identity.mismatches)
        if let focusPath { result = result.filter { $0.enginePath == focusPath || $0.isGlobal } }
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            result = result.filter {
                $0.friendlyName.lowercased().contains(needle)
                    || $0.enginePath.lowercased().contains(needle)
                    || $0.targetDescription.lowercased().contains(needle)
            }
        }
        // „Schimbări recente” își păstrează ordinea cronologică.
        return sidebar == .recentChanges ? result : result.sorted(using: sortOrder)
    }

    private func copy(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func export(_ rules: [FirewallRule], name: String) {
        status = RuleExporter.save(rules, suggestedName: "GDC Firewall – " + name)
    }

    /// Executabil mutat/redenumit: alegi noua lui locație, regula se mută acolo.
    private func repair(_ rule: FirewallRule) {
        let panel = NSOpenPanel()
        panel.message = L("Unde se află acum „%@”?", rule.processName)
        panel.allowedContentTypes = [.application, .unixExecutable, .executable, .item]
        panel.directoryURL = rule.fileURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bridge.repairPath(of: rule, to: url.path)
        status = L("Calea regulii a fost mutată la %@", url.path)
    }
}

// MARK: - Bara laterală

private struct RuleSidebar: View {
    @Binding var selection: SidebarItem?
    let onExport: ([FirewallRule], String) -> Void
    let onDeleteGroup: ([FirewallRule]) -> Void
    @ObservedObject private var bridge = DaemonBridge.shared
    @ObservedObject private var identity = IdentityChecker.shared
    @ObservedObject private var blocklist = BlocklistStore.shared
    @State private var addingBlocklist = false

    var body: some View {
        List(selection: $selection) {
            Section(L("Reguli")) {
                row(.all)
                row(.active)
                row(.deny)
                row(.recentChanges)
                row(.temporary)
                row(.unapproved, badge: true)
            }
            Section(L("Grupuri de reguli")) {
                ForEach(RuleGroup.allCases) { group in groupRow(group) }
            }
            Section(L("Sugestii")) {
                row(.expired, badge: true)
            }
            Section(L("Mentenanță")) {
                row(.redundant)
                row(.identityMismatch, badge: true)
                row(.noIdentityCheck)
                row(.missingExecutable, badge: true)
            }
            Section(L("Blocklist-uri")) {
                HStack {
                    Label("StevenBlack", systemImage: SidebarItem.blocklist.systemImage)
                    Spacer()
                    Text(blocklist.isEnabled ? blocklist.domainCount.formatted() : L("oprit"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(get: { blocklist.isEnabled }, set: { blocklist.setEnabled($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                .tag(SidebarItem.blocklist)
                ForEach(blocklist.customLists) { list in
                    Label(list.name, systemImage: "list.bullet.rectangle")
                        .foregroundStyle(list.isEnabled ? .primary : .secondary)
                        .tag(SidebarItem.blocklist)
                }
                Button {
                    addingBlocklist = true
                } label: {
                    Label(L("Adaugă blocklist…"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $addingBlocklist) { AddBlocklistSheet() }
    }

    private func count(_ item: SidebarItem) -> Int {
        RuleAnalysis.rules(for: item, in: bridge.rules, mismatches: identity.mismatches).count
    }

    @ViewBuilder
    private func row(_ item: SidebarItem, badge: Bool = false) -> some View {
        let n = count(item)
        if badge {
            Label(item.title, systemImage: item.systemImage)
                .badge(n)
                .tag(item)
        } else {
            HStack {
                Label(item.title, systemImage: item.systemImage)
                Spacer()
                Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .tag(item)
        }
    }

    private func groupRow(_ group: RuleGroup) -> some View {
        let rules = RuleAnalysis.rules(for: .group(group), in: bridge.rules, mismatches: [])
        let enabled = rules.contains { !$0.isDisabled }
        return HStack {
            Label(group.title, systemImage: group.systemImage)
            Spacer()
            Text("\(rules.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Toggle("", isOn: Binding(get: { enabled }, set: { bridge.setEnabled($0, for: rules) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(rules.isEmpty)
                .help(L("Activează sau dezactivează tot grupul"))
        }
        .tag(SidebarItem.group(group))
        .contextMenu {
            Button(L("Editează")) { selection = .group(group) }
            Button(L("Exportă regulile…")) { onExport(rules, group.title) }
                .disabled(rules.isEmpty)
            Button(enabled ? L("Dezactivează grupul") : L("Activează grupul")) { bridge.setEnabled(!enabled, for: rules) }
                .disabled(rules.isEmpty)
            Divider()
            Button(L("Șterge…"), role: .destructive) { onDeleteGroup(rules) }
                .disabled(rules.isEmpty)
        }
    }
}

// MARK: - Piese

private struct RuleStateBadge: View {
    let rule: FirewallRule

    var body: some View {
        if rule.isDisabled {
            Label(L("Dezactivată"), systemImage: "pause.circle")
                .foregroundStyle(.secondary)
        } else {
            Label(rule.action.label, systemImage: rule.action == .allow ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(rule.action.tint)
        }
    }
}

extension FirewallRule {
    /// Chei de sortare pentru coloanele tabelului (trebuie să fie `Comparable`).
    var stateSortKey: Int { isDisabled ? 2 : action.rawValue }
    var creationSortKey: Date { creation ?? .distantPast }
}

extension View {
    /// `.inspector` există doar din macOS 14; aplicația pornește din 13, unde
    /// același panou stă într-un `HSplitView` redimensionabil.
    @ViewBuilder
    func inspectorCompat<Content: View>(isPresented: Binding<Bool>, enabled: Bool,
                                        @ViewBuilder content: () -> Content) -> some View {
        if !enabled {
            self
        } else if #available(macOS 14.0, *) {
            self.inspector(isPresented: isPresented) {
                content().inspectorColumnWidth(min: 260, ideal: 320, max: 520)
            }
        } else {
            HSplitView {
                self.frame(minWidth: 360, maxWidth: .infinity)
                if isPresented.wrappedValue {
                    content().frame(minWidth: 260, idealWidth: 320, maxWidth: 520)
                }
            }
        }
    }
}
