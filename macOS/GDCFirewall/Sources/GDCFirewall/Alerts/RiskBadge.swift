import SwiftUI

/// Insigna circulară a semaforului. E primul lucru pe care îl vede
/// utilizatorul în alertă, deci poartă și culoarea, și simbolul, și — la
/// nevoie — textul: culoarea singură nu e accesibilă pentru cineva cu
/// daltonism, iar un firewall care se bazează pe „verde vs roșu” e un
/// firewall care induce în eroare exact utilizatorii pe care îi protejează.
struct RiskBadge: View {
    let risk: RiskLevel
    var diameter: CGFloat = 76

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(risk.tint.opacity(0.16))
                .overlay(Circle().strokeBorder(risk.tint.opacity(0.55), lineWidth: 2))
                .scaleEffect(pulse ? 1.06 : 1.0)

            Image(systemName: risk.systemImage)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(risk.tint)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            // Micro-animație doar pe roșu, doar dacă utilizatorul n-a cerut
            // mai puțină mișcare. Pe verde ar fi zgomot vizual gratuit.
            guard risk == .unknown, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Nivel de risc: \(risk.title)")
    }
}

/// Varianta mică, pentru rândurile din Rules Manager.
struct RiskDot: View {
    let risk: RiskLevel

    var body: some View {
        Circle()
            .fill(risk.tint)
            .frame(width: 8, height: 8)
            .accessibilityLabel(risk.title)
    }
}
