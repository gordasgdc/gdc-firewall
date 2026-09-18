import AppKit
import SwiftUI
import Combine

/// Prezintă alertele una câte una. Motivul pentru care există un
/// controller și nu doar un `.sheet`: alerta trebuie să apară peste orice,
/// inclusiv peste aplicații în ecran complet, iar aplicația rulează ca
/// `LSUIElement` (fără fereastră principală care s-o găzduiască).
final class AlertWindowController: NSObject, NSWindowDelegate {
    static let shared = AlertWindowController()

    private var window: NSWindow?
    private var cancellable: AnyCancellable?

    private override init() { super.init() }

    func start() {
        cancellable = DaemonBridge.shared.$pendingAlerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                guard let self else { return }
                if let next = queue.first {
                    self.present(next)
                } else {
                    self.close()
                }
            }
    }

    private func present(_ request: ConnectionRequest) {
        // Dacă fereastra arată deja aceeași cerere, n-o reconstruim —
        // altfel utilizatorul vede alerta „clipind” la fiecare actualizare.
        if let window, window.identifier?.rawValue == request.id.uuidString {
            window.makeKeyAndOrderFront(nil)
            return
        }
        close()

        let view = AlertView(request: request) { verdict in
            DaemonBridge.shared.submit(verdict)
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(request.id.uuidString)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: view)
        // Redimensionabilă (texte lungi, text mărit), dar nu sub lățimea la
        // care butoanele încap pe un rând.
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.delegate = self
        window.center()

        // Alerta nu are buton de închidere: singurele ieșiri sunt
        // „Permite” și „Blochează”. O alertă de firewall pe care o poți
        // face să dispară fără să decizi e o alertă care nu protejează.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}
