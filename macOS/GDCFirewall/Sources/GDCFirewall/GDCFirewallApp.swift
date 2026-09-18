import SwiftUI
import AppKit

@main
struct GDCFirewallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Aplicația trăiește în bara de meniu (`LSUIElement`): fereastra de
        // reguli și alertele se deschid la cerere, nu la pornire.
        MenuBarExtra("GDC Firewall", systemImage: "shield.lefthalf.filled") {
            MenuBarContent()
        }

        Settings {
            SettingsView()
        }

        Window("Reguli", id: "rules") {
            RulesManagerView()
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
        if bridge.isConnected { return "Protecție activă" }
        switch sysex.state {
        case .requesting: return "Se activează extensia…"
        case .needsApproval: return "Aprobă extensia în Setări de sistem"
        case .failed(let reason): return "Extensia nu a pornit: \(reason)"
        case .unknown, .active: return "Motor oprit"
        }
    }

    var body: some View {
        Text(statusText)

        Divider()

        Button("Reguli…") { openWindow(id: "rules") }
            .keyboardShortcut("r")

        Toggle("Mod Silențios", isOn: $autoPilot.isEnabled)

        Divider()

        Button("Verifică actualizări…") { UpdateChecker.shared.checkManually() }
        Button("Despre GDC Firewall") { AuxWindowPresenter.showAbout() }

        Divider()

        Button("Ieșire") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMover.promptIfNeeded()
        #if !SWIFT_PACKAGE
        // Fără cererea asta extensia nu ajunge niciodată la macOS: nu apare în
        // Setări de sistem și nu cere aprobare. Harnașamentul SPM n-are extensie.
        SystemExtensionInstaller.shared.activate()
        #endif
        _ = ThemeManager.shared
        DaemonBridge.shared.connect()
        AlertWindowController.shared.start()
        BlocklistStore.shared.refresh()
        UpdateChecker.shared.checkAtLaunch()
    }
}
