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
        // Bară de titlu standard, unificată cu toolbar-ul: cu `.hiddenTitleBar`
        // conținutul urca sub butoanele de fereastră și acoperea bara laterală.
        .defaultSize(width: 1100, height: 680)
    }
}

private struct MenuBarContent: View {
    @ObservedObject private var bridge = DaemonBridge.shared
    @ObservedObject private var autoPilot = AutoPilot.shared
    @ObservedObject private var sysex = SystemExtensionInstaller.shared
    @ObservedObject private var blocklist = BlocklistStore.shared
    @Environment(\.openWindow) private var openWindow

    /// Până la aprobarea din Setări aplicația pare pornită și nu filtrează
    /// nimic — starea extensiei se spune explicit, nu se ascunde sub „oprit”.
    private var statusText: String {
        switch sysex.phase {
        case .replacing: return L("Se actualizează motorul de filtrare…")
        case .deferred: return L("Actualizarea motorului e amânată")
        case .needsReboot: return L("Repornește Mac-ul pentru a finaliza actualizarea")
        case .idle: break
        }
        if sysex.state == .filterOff { return L("Filtrare oprită") }
        if bridge.isConnected { return L("Protecție activă") }
        switch sysex.state {
        case .active:
            // Regulile se aplică în continuare; doar legătura cu interfața lipsește.
            return L("Se reconectează la motor…")
        case .requesting: return L("Se activează extensia…")
        case .needsApproval: return L("Aprobă extensia în Setări de sistem")
        case .failed(let reason): return L("Extensia nu a pornit: %@", reason)
        case .unknown, .filterOff: return L("Motor oprit")
        }
    }

    var body: some View {
        Text(statusText)
        if sysex.phase == .deferred {
            Button(L("Finalizează actualizarea motorului…")) { sysex.finishEngineUpdate() }
        }

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
        Menu(L("Blocklist")) {
            Toggle(L("Blocklist StevenBlack"), isOn: Binding(get: { blocklist.isEnabled }, set: { blocklist.setEnabled($0) }))
            Divider()
            ForEach(BlocklistTier.allCases) { tier in
                Toggle(tier.title, isOn: Binding(get: { blocklist.tiers.contains(tier) }, set: { blocklist.setTier(tier, enabled: $0) }))
            }
            .disabled(!blocklist.isEnabled)
            Divider()
            Text(blocklist.isUpdating ? L("Se actualizează…") : L("%@ domenii blocate", blocklist.domainCount.formatted()))
            Button(L("Actualizează acum")) { blocklist.refresh() }
                .disabled(blocklist.isUpdating || !blocklist.isEnabled)
            Button(L("Detalii blocklist…")) { openWindow(id: "rules") }
        }
        Button(L("Importă reguli din alte firewall-uri…")) { AuxWindowPresenter.showSetup() }

        Divider()

        Button(L("Verifică actualizări…")) { UpdateChecker.shared.checkManually() }
        SettingsButton()
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
