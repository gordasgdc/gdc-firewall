import AppKit
import SwiftUI

/// Versiunea aplicației, pentru subsolul barei laterale și meniu (Regula 7).
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

/// Butonul „Setări…” din bara laterală a ferestrei Reguli și din meniul din
/// bara de sus.
///
/// Aplicația trăiește doar în bara de meniu (`LSUIElement`), deci trebuie
/// activată explicit, altfel fereastra Setări se deschide în spatele celorlalte.
/// Din macOS 14 singura cale sigură e `openSettings`; pe 13, acțiunea
/// `showSettingsWindow:` (pe 14+ e ignorată și doar loghează un avertisment).
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            Modern()
        } else {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label(L("Setări…"), systemImage: "gearshape")
            }
            .keyboardShortcut(",")
        }
    }

    @available(macOS 14.0, *)
    private struct Modern: View {
        @Environment(\.openSettings) private var openSettings

        var body: some View {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label(L("Setări…"), systemImage: "gearshape")
            }
            .keyboardShortcut(",")
        }
    }
}
