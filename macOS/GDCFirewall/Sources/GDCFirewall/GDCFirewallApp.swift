import SwiftUI
import AppKit

@main
struct GDCFirewallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Schimbarea limbii din Setări reconstruiește ferestrele deschise.
    @AppStorage(Lang.preferenceKey) private var language = Lang.systemValue

    var body: some Scene {
        // Aplicația trăiește în bara de meniu (`LSUIElement`): fereastra de
        // reguli și alertele se deschid la cerere, nu la pornire.
        MenuBarExtra("GDC Firewall", systemImage: "shield.lefthalf.filled") {
            MenuBarContent().id(language)
        }

        Settings {
            SettingsView().id(language)
        }

        Window(L("Reguli"), id: "rules") {
            RulesManagerView().id(language)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 600)
    }
}

private struct MenuBarContent: View {
    @ObservedObject private var bridge = DaemonBridge.shared
    @ObservedObject private var autoPilot = AutoPilot.shared
    @ObservedObject private var sysex = SystemExtensionInstaller.shared
    @Environment(\.openWindow) private var openWindow

    /// Până la aprobarea din Setări aplicația pare pornită și nu filtrează
    /// nimic — starea extensiei se spune explicit, nu se ascunde sub „oprit”.
    private var statusText: String {
        if sysex.state == .filterOff { return L("Filtrare oprită") }
        if bridge.isConnected { return L("Protecție activă") }
        switch sysex.state {
        case .active where bridge.failedReconnects >= DaemonBridge.restartHintThreshold:
            // Filtrul rulează, dar fără interfață: motorul permite tot, fără
            // alerte. Cauza cunoscută: înlocuirea extensiei la actualizare.
            return L("Repornește Mac-ul pentru a finaliza actualizarea")
        case .requesting: return L("Se activează extensia…")
        case .needsApproval: return L("Aprobă extensia în Setări de sistem")
        case .failed(let reason): return L("Extensia nu a pornit: %@", reason)
        case .unknown, .active, .filterOff: return L("Motor oprit")
        }
    }

    var body: some View {
        Text(statusText)

        if sysex.state == .active || sysex.state == .filterOff {
            Toggle(L("Filtrare activă"), isOn: Binding(
                get: { sysex.state == .active },
                set: { sysex.setFilterEnabled($0) }
            ))
        }

        Divider()

        Button(L("Reguli…")) { openWindow(id: "rules") }
            .keyboardShortcut("r")

        Toggle(L("Mod Silențios"), isOn: $autoPilot.isEnabled)
        Button(L("Importă reguli din alte firewall-uri…")) { AuxWindowPresenter.showSetup() }

        Divider()

        Button(L("Verifică actualizări…")) { UpdateChecker.shared.checkManually() }
        Button(L("Despre GDC Firewall")) { AuxWindowPresenter.showAbout() }

        Divider()

        Button(L("Ieșire")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = DiagnosticLog("app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary
        log.info("Pornire GDC Firewall \(info?["CFBundleShortVersionString"] ?? "?") (build \(info?["CFBundleVersion"] ?? "?"))"
            + " · motor LuLu \(LuLu.engineVersion) · \(ProcessInfo.processInfo.operatingSystemVersionString)"
            + " · limbă \(Lang.current.rawValue) · \(Bundle.main.bundlePath)")
        AppMover.promptIfNeeded()
        #if !SWIFT_PACKAGE
        // Fără cererea asta extensia nu ajunge niciodată la macOS: nu apare în
        // Setări de sistem și nu cere aprobare. Harnașamentul SPM n-are extensie.
        SystemExtensionInstaller.shared.activate()
        FirstRunSetup.showIfNeeded()
        #endif
        _ = ThemeManager.shared
        DaemonBridge.shared.connect()
        AlertWindowController.shared.start()
        BlocklistStore.shared.refresh()
        UpdateChecker.shared.checkAtLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("Oprire GDC Firewall")
        DiagnosticLog.flush()
    }
}
