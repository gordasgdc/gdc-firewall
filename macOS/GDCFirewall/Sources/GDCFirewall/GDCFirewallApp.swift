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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(bridge.isConnected ? "Protecție activă" : "Motor oprit")

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
        _ = ThemeManager.shared
        DaemonBridge.shared.connect()
        AlertWindowController.shared.start()
        BlocklistStore.shared.refresh()
        UpdateChecker.shared.checkAtLaunch()
    }
}
