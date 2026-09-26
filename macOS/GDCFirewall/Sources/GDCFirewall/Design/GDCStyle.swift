import SwiftUI
import AppKit

/// Fundația vizuală GDC Firewall: spațiere, tipografie, tonuri de stare și
/// suprafețe. Minimă intenționat — componentele rămân cele native macOS;
/// aici stau doar valorile care altfel s-ar repeta, diferit, prin ecrane.
enum GDCStyle {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 18
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 10
    }
}

// MARK: - Tonuri de stare

/// Starea semantică a unui lucru afișat: reușită, atenție, funcționare
/// degradată, eroare, neutru. Singurul loc din aplicație unde o stare primește
/// culoare și simbol — ecranele nu scriu `.red`/`.green` direct (Regula 37).
///
/// Culoarea nu poartă niciodată singură informația: fiecare ton are și un
/// simbol cu formă proprie.
enum StatusTone: CaseIterable {
    case success, attention, degraded, error, neutral

    /// Pentru simboluri, fundaluri și contururi (nu pentru text).
    var tint: Color { Color(nsColor: tintColor) }

    /// Pentru TEXT colorat: variantă mai închisă în Light, ca textul să treacă
    /// pragul de contrast 4.5:1 pe fundalul ferestrei (verificat în teste).
    /// Galbenul sistemului pe alb e ~1.5:1 — ilizibil ca text.
    var foreground: Color { Color(nsColor: foregroundColor) }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .degraded: return "arrow.triangle.2.circlepath"
        case .error: return "xmark.octagon.fill"
        case .neutral: return "info.circle"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .success: return .systemGreen
        case .attention: return .systemYellow
        case .degraded: return .systemOrange
        case .error: return .systemRed
        case .neutral: return .secondaryLabelColor
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .success: return Self.dynamic(light: (0.10, 0.45, 0.20), dark: .systemGreen)
        case .attention: return Self.dynamic(light: (0.52, 0.36, 0.00), dark: .systemYellow)
        case .degraded: return Self.dynamic(light: (0.62, 0.28, 0.00), dark: .systemOrange)
        case .error: return Self.dynamic(light: (0.72, 0.13, 0.11), dark: .systemRed)
        case .neutral: return .secondaryLabelColor
        }
    }

    private static func dynamic(light rgb: (CGFloat, CGFloat, CGFloat), dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark
                : NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }
}

// MARK: - Mărimea textului

/// Mărimea textului, aleasă din Setări. `dynamicTypeSize` NU are efect pe
/// macOS (măsurat: aceeași lățime a textului la toate treptele), deci scalarea
/// se face aici, centralizat: fiecare stil are mărimea de bază macOS
/// înmulțită cu factorul ales.
enum TextSize: String, CaseIterable, Identifiable {
    case standard, large, larger

    static let preferenceKey = "GDCFirewall.textSize"
    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .standard: return 1.0
        case .large: return 1.15
        case .larger: return 1.3
        }
    }

    var label: String {
        switch self {
        case .standard: return L("Standard")
        case .large: return L("Mare")
        case .larger: return L("Foarte mare")
        }
    }

    static var current: TextSize {
        TextSize(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .standard
    }
}

/// Stilurile de text folosite de ecranele GDC, cu mărimile de bază macOS.
enum GDCTextStyle {
    case title, headline, body, callout, caption, caption2, mono

    var baseSize: CGFloat {
        switch self {
        case .title: return 15
        case .headline, .body: return 13
        case .callout: return 12
        case .caption, .mono: return 10.5
        case .caption2: return 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .title, .headline: return .semibold
        default: return .regular
        }
    }

    func size(scale: CGFloat) -> CGFloat { (baseSize * scale).rounded() }

    func font(scale: CGFloat) -> Font {
        self == .mono
            ? .system(size: size(scale: scale), weight: weight, design: .monospaced)
            : .system(size: size(scale: scale), weight: weight)
    }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var gdcTextScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct GDCFontModifier: ViewModifier {
    let style: GDCTextStyle
    @Environment(\.gdcTextScale) private var scale
    func body(content: Content) -> some View { content.font(style.font(scale: scale)) }
}

/// Aplică mărimea aleasă de utilizator la rădăcina unei ferestre; textul fără
/// stil explicit primește corpul scalat, cel cu `.gdcFont(_:)` stilul lui scalat.
private struct TextScaleRoot: ViewModifier {
    @AppStorage(TextSize.preferenceKey) private var stored = TextSize.standard.rawValue
    func body(content: Content) -> some View {
        let scale = (TextSize(rawValue: stored) ?? .standard).scale
        content
            .environment(\.gdcTextScale, scale)
            .font(GDCTextStyle.body.font(scale: scale))
    }
}

// MARK: - Suprafețe

/// Fundalul unei ferestre GDC: material nativ, iar cu „Redu transparența”
/// activ, culoarea opacă a ferestrei (fără blur).
private struct WindowSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else {
            content.background(VisualEffectView())
        }
    }
}

extension View {
    func gdcFont(_ style: GDCTextStyle) -> some View { modifier(GDCFontModifier(style: style)) }
    func gdcTextScaleRoot() -> some View { modifier(TextScaleRoot()) }
    func gdcWindowSurface() -> some View { modifier(WindowSurface()) }
}

// MARK: - Contrast

enum Contrast {
    /// Raportul WCAG între două culori (1…21).
    static func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    /// Culoarea dinamică rezolvată într-o anumită apariție (Light/Dark).
    static func resolve(_ color: NSColor, dark: Bool) -> NSColor {
        var resolved = color
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}
