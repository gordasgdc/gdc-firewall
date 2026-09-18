import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            FilteringSettings()
                .tabItem { Label(L("Filtrare & AdBlock"), systemImage: "shield.lefthalf.filled") }
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var autoPilot = AutoPilot.shared
    @ObservedObject private var theme = ThemeManager.shared
    @AppStorage(Lang.preferenceKey) private var language = Lang.systemValue

    var body: some View {
        Form {
            Section {
                Toggle(L("Mod Silențios (Aprobare inteligentă)"), isOn: $autoPilot.isEnabled)
                Text(L("Aprobă automat serviciile semnate oficial de Apple, ca să nu te întreb de zeci de ori despre componente ale macOS. Tot ce nu e Apple te întreabă în continuare, de fiecare dată."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !autoPilot.silentlyApproved.isEmpty {
                    DisclosureGroup(L("Aprobate automat (%d)", autoPilot.silentlyApproved.count)) {
                        ForEach(autoPilot.silentlyApproved, id: \.self) { name in
                            Text(name).font(.caption)
                        }
                        Button(L("Golește jurnalul")) { autoPilot.clearLog() }
                            .buttonStyle(.link)
                    }
                }
            } header: {
                Text(L("Alerte"))
            }

            Section {
                Picker(L("Temă"), selection: Binding(
                    get: { theme.current },
                    set: { theme.set($0) }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("Limbă"), selection: $language) {
                    Text(L("Sistem")).tag(Lang.systemValue)
                    ForEach(Lang.allCases) { Text($0.endonym).tag($0.rawValue) }
                }
            } header: {
                Text(L("Aspect"))
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Filtrare & AdBlock

/// Aceeași vizualizare ca în fereastra Reguli → Blocklist-uri.
private struct FilteringSettings: View {
    var body: some View { BlocklistView() }
}
