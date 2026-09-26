import XCTest
import SwiftUI
import AppKit
@testable import GDCFirewall

/// Capturi Light/Dark × RO/EN ale ferestrelor principale, randate offscreen
/// (NSHostingView → bitmap). Rulează DOAR cu `GDC_SNAPSHOT_DIR=<folder>`:
///
///     GDC_SNAPSHOT_DIR=/cale swift test --filter SnapshotCapture
///
/// Nu e un test de regresie vizuală (nu compară pixeli): produce dovezi
/// înainte/după pentru verificare umană. Meniul din bara de sus NU este un
/// NSMenu real: captura `menu-harness-*` este doar simularea SwiftUI offscreen
/// și nu constituie dovadă pentru stările reale din menubar.
@MainActor
final class SnapshotCapture: XCTestCase {
    private var outputDir: URL!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["GDC_SNAPSHOT_DIR"] else {
            throw XCTSkip("GDC_SNAPSHOT_DIR nesetat")
        }
        outputDir = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        _ = NSApplication.shared
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Lang.preferenceKey)
    }

    func testCaptureAll() throws {
        let requests: [(String, ConnectionRequest)] = [
            ("apple", Fixtures.request(path: "/usr/libexec/nsurlsessiond", name: nil, signingID: "com.apple.nsurlsessiond", signer: LuLu.Signer.apple, host: "apple.com")),
            ("devid", Fixtures.request()),
            ("unsigned", Fixtures.request(path: "/Users/test/Downloads/tool", name: nil, signingID: nil, signer: LuLu.Signer.none, host: "198.51.100.9", port: "8080")),
        ]
        var written = 0
        for lang in ["ro", "en"] {
            UserDefaults.standard.set(lang, forKey: Lang.preferenceKey)
            for dark in [false, true] {
                let suffix = "\(lang)-\(dark ? "dark" : "light")"
                for (name, view) in SnapshotViews.settings() {
                    written += try render(view, size: CGSize(width: 640, height: 520), dark: dark, name: "settings-\(name)-\(suffix)")
                }
                for (name, request) in requests {
                    written += try render(AnyView(AlertView(request: request) { _ in }), size: CGSize(width: 460, height: 560), dark: dark, name: "alert-\(name)-\(suffix)")
                }
                if let menu = SnapshotViews.menuHarness() {
                    written += try render(menu, size: CGSize(width: 360, height: 720), dark: dark, name: "menu-harness-\(suffix)")
                }
            }
        }
        print("SNAPSHOT: \(written) imagini în \(outputDir.path)")
    }

    /// Scrie PNG-ul și întoarce 1; pică dacă imaginea e uniformă (randare goală).
    private func render(_ view: AnyView, size: CGSize, dark: Bool, name: String) throws -> Int {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = appearance
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw XCTSkip("bitmap indisponibil") }
        appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    colors.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
                }
            }
        }
        XCTAssertGreaterThan(colors.count, 8, "randare aproape goală: \(name)")
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: outputDir.appendingPathComponent("\(name).png"))
        return 1
    }
}
