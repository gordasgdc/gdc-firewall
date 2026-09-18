import AppKit
import SwiftUI

/// Prezintă ferestre native auxiliare (Help/About) hostuind conținut
/// SwiftUI — separate de overlay-ul principal (`OverlayWindowController`),
/// ca userul să poată avea Dashboard-ul deschis ȘI ghidul/About în același timp.
///
/// `@MainActor`: AppKit aruncă o excepție (și oprește aplicația) dacă un
/// `NSWindow` e creat în afara firului principal — exact crash-ul de la pornire
/// din v2.1.0–2.2.1. Compilatorul refuză acum orice apel de pe alt fir.
@MainActor
enum AuxWindowPresenter {
    private static var controllers: [String: NSWindowController] = [:]

    static func present<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let existing = controllers[id], let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: content())

        let controller = NSWindowController(window: window)
        controllers[id] = controller

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in controllers[id] = nil }
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close(id: String) {
        controllers[id]?.close()
    }
}

extension AuxWindowPresenter {
    static func showAbout() {
        present(id: "about", title: L("Despre GDC Firewall"), size: NSSize(width: 340, height: 360)) {
            AboutView()
        }
    }
}
