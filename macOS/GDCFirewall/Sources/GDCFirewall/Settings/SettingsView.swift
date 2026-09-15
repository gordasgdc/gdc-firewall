import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FilteringSettings()
                .tabItem { Label("Filtrare & AdBlock", systemImage: "shield.lefthalf.filled") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var autoPilot = AutoPilot.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Mod Silențios (Aprobare inteligentă)", isOn: $autoPilot.isEnabled)
                Text("Aprobă automat serviciile semnate oficial de Apple, ca să nu te întreb de zeci de ori despre componente ale macOS. Tot ce nu e Apple te întreabă în continuare, de fiecare dată.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !autoPilot.silentlyApproved.isEmpty {
                    DisclosureGroup("Aprobate automat (\(autoPilot.silentlyApproved.count))") {
                        ForEach(autoPilot.silentlyApproved, id: \.self) { name in
                            Text(name).font(.caption)
                        }
                        Button("Golește jurnalul") { autoPilot.clearLog() }
                            .buttonStyle(.link)
                    }
                }
            } header: {
                Text("Alerte")
            }

            Section {
                Picker("Temă", selection: Binding(
                    get: { theme.current },
                    set: { theme.set($0) }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Aspect")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Filtrare & AdBlock

/// Nivelele de blocare a domeniilor. Sunt trei comutatoare, nu un slider,
/// fiindcă fiecare nivel răspunde la o întrebare diferită — iar „Maxim”
/// (pornografie/pariuri) e o alegere personală, nu un pas de securitate
/// mai avansat.
private struct FilteringSettings: View {
    @ObservedObject private var store = BlocklistStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(BlocklistLevel.allCases) { level in
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(level.title, isOn: Binding(
                            get: { store.enabledLevels.contains(level) },
                            set: { store.setLevel(level, enabled: $0) }
                        ))
                        Text(level.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Nivele de filtrare")
            } footer: {
                Text("Nivelele se adună: dacă bifezi Maxim, primești și ce blochează Minim și Mediu.")
                    .font(.caption)
            }

            Section {
                LabeledContent("Domenii în listă") {
                    Text(store.domainCount == 0 ? "—" : "\(store.domainCount)")
                        .monospacedDigit()
                }
                LabeledContent("Ultima actualizare") {
                    if let date = store.lastUpdated {
                        Text(date, style: .relative) + Text(" în urmă")
                    } else {
                        Text("niciodată")
                    }
                }

                HStack {
                    Button("Actualizare liste") { store.refresh() }
                        .disabled(store.isUpdating || store.enabledLevels.isEmpty)
                    if store.isUpdating {
                        ProgressView().controlSize(.small)
                    }
                }

                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Listele")
            } footer: {
                Text("Sursa e proiectul open-source StevenBlack/hosts. Listele se țin local, în memorie — filtrarea nu trimite nimic în afară și nu încetinește navigarea.")
                    .font(.caption)
            }

            if !store.allowList.isEmpty {
                Section("Excepții (permise de tine)") {
                    ForEach(Array(store.allowList).sorted(), id: \.self) { host in
                        HStack {
                            Text(host).font(.caption.monospaced())
                            Spacer()
                            Button("Elimină") { store.removeFromAllowList(host) }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
