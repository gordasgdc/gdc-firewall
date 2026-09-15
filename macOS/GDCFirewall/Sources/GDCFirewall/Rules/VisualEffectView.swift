import SwiftUI
import AppKit

/// Sticla mată de sub tot ce e „panou” în aplicație. SwiftUI-ul nativ
/// (`.background(.ultraThinMaterial)`) acoperă 90% din cazuri, dar nu poate
/// cere un material de FEREASTRĂ (`.underWindowBackground`) — de aia
/// rămâne acest wrapper peste `NSVisualEffectView`.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active          // .active, nu .followsWindowActiveState:
        view.material = material      // altfel panoul devine gri mort când
        view.blendingMode = blending  // fereastra pierde focusul.
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = isEmphasized
    }
}

/// Cardul standard al aplicației: sticlă + contur subțire + colț rotund.
/// Orice panou îl folosește, ca să nu apară trei raze de colț diferite.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}
