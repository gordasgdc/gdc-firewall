import SwiftUI

/// Blocklist-ul StevenBlack pe niveluri + listele personalizate. Aceeași
/// vedere apare în fereastra Reguli (bara laterală → Blocklist-uri) și în
/// Setări → Filtrare.
struct BlocklistView: View {
    @ObservedObject private var store = BlocklistStore.shared
    @State private var probe = ""
    @State private var newException = ""
    @State private var addingList = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Blocklist StevenBlack")).font(.headline)
                        Text(store.isEnabled
                             ? L("%@ domenii blocate", store.domainCount.formatted())
                             : L("Oprit — nu se blochează niciun domeniu din liste."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                HStack {
                    Button(L("Actualizează acum")) { store.refresh() }
                        .disabled(store.isUpdating || !store.isEnabled)
                    if store.isUpdating { ProgressView().controlSize(.small) }
                    Spacer()
                    Text(store.lastUpdated.map { L("Actualizat: %@", Self.relative($0)) } ?? L("Neactualizat încă"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.caption)
                }
            } footer: {
                Text(L("Blocarea o face motorul de filtrare, pentru fiecare conexiune a fiecărei aplicații — inclusiv a celor deja permise."))
                    .font(.caption)
            }

            Section(L("Niveluri")) {
                Toggle(isOn: .constant(true)) {
                    tierLabel(L("Unified (bază)"), L("Reclame, malware și urmărire — baza pe care se adaugă celelalte."))
                }
                .disabled(true)
                ForEach(BlocklistTier.allCases) { tier in
                    Toggle(isOn: Binding(get: { store.tiers.contains(tier) }, set: { store.setTier(tier, enabled: $0) })) {
                        tierLabel(tier.title, tier.summary)
                    }
                }
            }
            .disabled(!store.isEnabled)

            if !store.sourceCounts.isEmpty {
                Section(L("Surse îmbinate")) {
                    ForEach(store.sourceCounts.indices, id: \.self) { index in
                        LabeledContent(store.sourceCounts[index].name) {
                            Text("+\(store.sourceCounts[index].count.formatted())").monospacedDigit()
                        }
                    }
                }
            }

            Section(L("Liste personalizate")) {
                ForEach(store.customLists) { list in
                    HStack {
                        Toggle(isOn: Binding(get: { list.isEnabled }, set: { store.setCustomList(list.id, enabled: $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                Text(list.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Button(role: .destructive) { store.removeCustomList(list.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help(L("Elimină"))
                    }
                }
                Button(L("Adaugă blocklist…")) { addingList = true }
            }
            .disabled(!store.isEnabled)

            Section(L("Verifică un domeniu")) {
                TextField(L("ex. doubleclick.net"), text: $probe)
                    .textFieldStyle(.roundedBorder)
                if !probe.trimmingCharacters(in: .whitespaces).isEmpty {
                    let blocked = store.isBlocked(probe.trimmingCharacters(in: .whitespaces))
                    Label(blocked ? L("Blocat de listă") : L("Nu e pe listă"),
                          systemImage: blocked ? "hand.raised.fill" : "checkmark.circle")
                        .foregroundStyle(blocked ? RuleAction.block.tint : .secondary)
                    if blocked {
                        Button(L("Permite acest domeniu")) {
                            store.allow(probe.trimmingCharacters(in: .whitespaces))
                        }
                    }
                }
            }

            Section(L("Excepții (permise de tine)")) {
                ForEach(Array(store.allowList).sorted(), id: \.self) { host in
                    HStack {
                        Text(host).font(.caption.monospaced())
                        Spacer()
                        Button(L("Elimină")) { store.removeFromAllowList(host) }
                            .buttonStyle(.link)
                    }
                }
                HStack {
                    TextField(L("domeniu de permis"), text: $newException)
                        .textFieldStyle(.roundedBorder)
                    Button(L("Adaugă")) {
                        store.allow(newException.trimmingCharacters(in: .whitespaces))
                        newException = ""
                    }
                    .disabled(newException.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 560, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .sheet(isPresented: $addingList) { AddBlocklistSheet() }
    }

    private func tierLabel(_ title: String, _ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: Lang.current.rawValue)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// „Adaugă blocklist…”: un URL cu o listă în format hosts sau un domeniu pe linie.
struct AddBlocklistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    private var isValid: Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme else { return false }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty && ["http", "https"].contains(scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Adaugă blocklist")).font(.headline)
            Text(L("O listă publică în format hosts (0.0.0.0 domeniu) sau cu un domeniu pe linie. Se îmbină cu StevenBlack la fiecare actualizare."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("Nume"), text: $name).textFieldStyle(.roundedBorder)
            TextField("https://…", text: $url).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L("Anulează"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Adaugă")) {
                    BlocklistStore.shared.addCustomList(name: name.trimmingCharacters(in: .whitespaces),
                                                        url: url.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 460, maxWidth: .infinity)
    }
}
