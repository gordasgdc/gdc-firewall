import SwiftUI
import AppKit

/// Setările, în cinci destinații — fiecare răspunde unei singure întrebări:
/// cum arată aplicația, cum mă protejează, e la zi, ce date păstrează local,
/// ce e sub capotă.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            ProtectionSettings()
                .tabItem { Label(L("Protecție"), systemImage: "shield.lefthalf.filled") }
            UpdateSettings()
                .tabItem { Label(L("Actualizări"), systemImage: "arrow.down.circle") }
            DiagnosticSettings()
                .tabItem { Label(L("Diagnostic"), systemImage: "stethoscope") }
            AdvancedSettings()
                .tabItem { Label(L("Avansat"), systemImage: "slider.horizontal.3") }
        }
        .frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity, minHeight: 420, idealHeight: 520, maxHeight: .infinity)
        .gdcTextScaleRoot()
    }
}

/// Explicația scurtă de sub un control: secundară, dar lizibilă.
private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .gdcFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var theme = ThemeManager.shared
    @AppStorage(Lang.preferenceKey) private var language = Lang.systemValue
    @AppStorage(TextSize.preferenceKey) private var textSize = TextSize.standard.rawValue

    var body: some View {
        Form {
            Section {
                Picker(L("Limba interfeței"), selection: $language) {
                    Text(L("Sistem")).tag(Lang.systemValue)
                    ForEach(Lang.allCases) { Text($0.endonym).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Note(L("„Sistem” urmează limba macOS. Schimbarea se aplică imediat."))
            } header: {
                Text(L("Limbă"))
            }

            Section {
                Picker(L("Temă"), selection: Binding(get: { theme.current }, set: { theme.set($0) })) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("Mărimea textului"), selection: $textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Note(L("Se aplică alertelor și Setărilor. Fereastra Reguli păstrează mărimea standard a tabelelor macOS."))
            } header: {
                Text(L("Aspect"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Protecție

struct ProtectionSettings: View {
    @ObservedObject private var autoPilot = AutoPilot.shared

    var body: some View {
        BlocklistView {
            Section {
                Toggle(L("Mod Silențios (Aprobare inteligentă)"), isOn: $autoPilot.isEnabled)
                    .toggleStyle(.switch)
                Note(L("Aprobă automat serviciile semnate oficial de Apple, ca să nu te întreb de zeci de ori despre componente ale macOS. Tot ce nu e Apple te întreabă în continuare, de fiecare dată."))
                if !autoPilot.silentlyApproved.isEmpty {
                    DisclosureGroup(L("Aprobate automat (%d)", autoPilot.silentlyApproved.count)) {
                        ForEach(autoPilot.silentlyApproved, id: \.self) { name in
                            Text(name).gdcFont(.caption)
                        }
                        Button(L("Golește jurnalul")) { autoPilot.clearLog() }
                            .buttonStyle(.link)
                    }
                }
            } header: {
                Text(L("Alerte"))
            }
        }
    }
}

// MARK: - Actualizări

struct UpdateSettings: View {
    @ObservedObject private var sysex = SystemExtensionInstaller.shared

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var updateState: (String, StatusTone) {
        switch sysex.phase {
        case .idle: return (L("Nicio actualizare în curs"), .neutral)
        case .replacing: return (L("Se actualizează motorul de filtrare…"), .degraded)
        case .needsReboot: return (L("Repornește Mac-ul pentru a finaliza actualizarea"), .attention)
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Versiunea aplicației"), value: appVersion)
                LabeledContent(L("Motorul de filtrare"), value: "LuLu \(LuLu.engineVersion)")
                LabeledContent(L("Stare")) {
                    StatusLabel(text: updateState.0, tone: updateState.1)
                }
            } header: {
                Text(L("Versiuni"))
            }

            Section {
                Button(L("Caută actualizări acum")) { UpdateChecker.shared.checkManually() }
                Note(L("GDC Firewall verifică automat la fiecare pornire. Rezultatul apare într-o fereastră separată, iar instalarea pornește doar după confirmarea ta."))
            }
        }
        .formStyle(.grouped)
    }
}

/// Starea cu simbol + text: culoarea nu poartă singură informația.
struct StatusLabel: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        Label {
            Text(text).foregroundStyle(tone == .neutral ? Color.primary : tone.foreground)
        } icon: {
            Image(systemName: tone.symbol).foregroundStyle(tone.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Diagnostic și confidențialitate

struct DiagnosticSettings: View {
    @ObservedObject private var sysex = SystemExtensionInstaller.shared
    @ObservedObject private var bridge = DaemonBridge.shared
    @State private var options = DiagnosticExporter.Options()
    @State private var verbose = DiagnosticLog.sessionVerbose
    @State private var exporting = false
    @State private var exported: URL?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Note(L("Jurnalele și pachetul de diagnostic rămân locale pe Mac. Pachetul nu este trimis automat nicăieri: numai tu alegi dacă și cui îl transmiți. Jurnalul include pornirile, starea extensiei, erorile și aplicațiile care au cerut conexiuni, cu destinațiile lor; are o limită de mărime și se reciclează singur."))
                LabeledContent(L("ID-ul sesiunii")) {
                    HStack {
                        Text(DiagnosticLog.sessionID).gdcFont(.mono).textSelection(.enabled)
                        Button(L("Copiază")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(DiagnosticLog.sessionID, forType: .string)
                        }
                    }
                }
                Button(L("Deschide folderul de jurnale")) {
                    NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.fileURL])
                }
                Toggle(L("Jurnal detaliat până la următoarea pornire"), isOn: $verbose)
                    .onChange(of: verbose) { DiagnosticLog.sessionVerbose = $0 }
            } header: {
                Text(L("Date locale"))
            }

            Section {
                Toggle(L("Include căile complete din dosarul tău personal"), isOn: $options.includePersonalPaths)
                Toggle(L("Include rapoartele de blocare ale GDC Firewall"), isOn: $options.includeCrashReports)
                Note(L("Pachetul este o arhivă ZIP salvată unde alegi tu. Nu se trimite automat: îl poți deschide și verifica înainte să-l trimiți cuiva. Numele contului, adresele de e-mail și valorile de tip parolă sau cheie sunt eliminate întotdeauna."))
                HStack {
                    Button(L("Exportă diagnosticul…")) { chooseDestination() }
                        .disabled(exporting)
                    if exporting { ProgressView().controlSize(.small) }
                }
                if let exported {
                    HStack {
                        StatusLabel(text: L("Salvat: %@", exported.lastPathComponent), tone: .success)
                        Spacer()
                        Button(L("Arată în Finder")) { NSWorkspace.shared.activateFileViewerSelecting([exported]) }
                    }
                }
                if let exportError {
                    StatusLabel(text: L("Exportul a eșuat: %@", exportError), tone: .error)
                }
            } header: {
                Text(L("Pachet de diagnostic"))
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let day = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "GDCFirewall-Diagnostic-\(day).zip"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exported = nil
        exportError = nil
        exporting = true
        let context = [
            "stare": MenuBarStatus.resolve(state: sysex.state, phase: sysex.phase, isConnected: bridge.isConnected).text,
            "extensie": "\(sysex.state)",
            "etapa actualizare": "\(sysex.phase)",
            "mod silentios": "\(AutoPilot.shared.isEnabled)",
            "blocklist": "\(BlocklistStore.shared.isEnabled)",
            "limba": Lang.current.rawValue,
            "tema": ThemeManager.shared.current.rawValue,
            "marime text": TextSize.current.rawValue,
        ]
        Task {
            do {
                _ = try await DiagnosticExporter.export(to: url, options: options, context: context)
                exported = url
            } catch {
                exportError = error.localizedDescription
            }
            exporting = false
        }
    }
}

// MARK: - Avansat

struct AdvancedSettings: View {
    let extensionIdentifier: String
    @ObservedObject private var sysex = SystemExtensionInstaller.shared
    @ObservedObject private var bridge = DaemonBridge.shared
    @StateObject private var uninstaller = SelfUninstaller()
    @State private var confirmUninstall = false

    init(extensionIdentifier: String = "dev.gordas.GDCFirewall.extension") {
        self.extensionIdentifier = extensionIdentifier
    }

    private var status: MenuBarStatus {
        MenuBarStatus.resolve(state: sysex.state, phase: sysex.phase, isConnected: bridge.isConnected)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Stare")) { StatusLabel(text: status.text, tone: status.tone) }
                LabeledContent(L("Conexiunile sunt filtrate"), value: status.isFiltering ? L("Da") : L("Nu"))
                LabeledContent(L("Identificator"), value: extensionIdentifier)
                if sysex.state == .needsApproval {
                    Button(L("Deschide Setări de sistem…")) { sysex.openApprovalSettings() }
                }
                if sysex.state == .active || sysex.state == .filterOff {
                    Toggle(L("Filtrare activă"), isOn: Binding(
                        get: { sysex.state == .active },
                        set: { sysex.setFilterEnabled($0) }))
                        .toggleStyle(.switch)
                }
            } header: {
                Text(L("Extensia de rețea"))
            }

            Section {
                Note(L("Elimină filtrul de rețea, extensia, preferințele și jurnalele, apoi mută aplicația la Coș."))
                HStack {
                    Button(L("Dezinstalează GDC Firewall…"), role: .destructive) { confirmUninstall = true }
                        .disabled(isRunning)
                    if isRunning {
                        ProgressView().controlSize(.small)
                        Text(phaseText).gdcFont(.caption).foregroundStyle(.secondary)
                    }
                }
                if case .failed(let reason) = uninstaller.phase {
                    StatusLabel(text: reason, tone: .error)
                }
            } header: {
                Text(L("Dezinstalare"))
            }
        }
        .formStyle(.grouped)
        .alert(L("Dezinstalezi GDC Firewall?"), isPresented: $confirmUninstall) {
            Button(L("Anulează"), role: .cancel) {}
            Button(L("Dezinstalează"), role: .destructive) {
                Task { await uninstaller.run(steps: .live) }
            }
        } message: {
            Text(UninstallSummary.text)
        }
    }

    private var isRunning: Bool {
        switch uninstaller.phase {
        case .deactivatingExtension, .removingData, .movingToTrash: return true
        default: return false
        }
    }

    private var phaseText: String {
        switch uninstaller.phase {
        case .deactivatingExtension: return L("Se dezactivează extensia (macOS poate cere parola)…")
        case .removingData: return L("Se șterg preferințele și jurnalele…")
        case .movingToTrash: return L("Se mută aplicația la Coș…")
        default: return ""
        }
    }
}

/// Ce face dezinstalarea — spus înainte, nu după.
enum UninstallSummary {
    static var text: String {
        [
            L("Se elimină: filtrul de rețea și extensia GDC Firewall (macOS poate cere parola de administrator), preferințele, jurnalele și memoria cache. Apoi aplicația este mutată la Coș și se închide."),
            L("Rămân: regulile tale, în %@, pentru o eventuală reinstalare.", SelfUninstaller.keptSystemPath),
            L("Protecția oferită de GDC Firewall se oprește imediat. Dacă macOS finalizează eliminarea extensiei abia la repornire, îți vom spune."),
        ].joined(separator: "\n\n")
    }
}
