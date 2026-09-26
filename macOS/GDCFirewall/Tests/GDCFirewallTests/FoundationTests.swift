import XCTest
import SwiftUI
import AppKit
@testable import GDCFirewall

/// Starea din bara de meniu, tonurile de culoare și mărimea textului.
final class MenuBarStatusTests: XCTestCase {
    typealias S = SystemExtensionInstaller.State

    func testResolutionTable() {
        let cases: [(S, SystemExtensionInstaller.Phase, Bool, MenuBarStatus)] = [
            (.active, .idle, true, .protected),
            (.active, .idle, false, .reconnecting),
            (.requesting, .idle, false, .activating),
            (.needsApproval, .idle, false, .needsApproval),
            (.filterOff, .idle, true, .filterOff),          // filtrul oprit bate conexiunea
            (.filterOff, .idle, false, .filterOff),
            (.failed("x"), .idle, false, .failed("x")),
            (.unknown, .idle, false, .stopped),
            (.active, .replacing, true, .updating),          // etapa de actualizare bate tot
            (.filterOff, .needsReboot, false, .rebootRequired),
        ]
        for (state, phase, connected, expected) in cases {
            XCTAssertEqual(MenuBarStatus.resolve(state: state, phase: phase, isConnected: connected), expected,
                           "\(state) / \(phase) / \(connected)")
        }
    }

    private let all: [MenuBarStatus] = [.protected, .needsApproval, .activating, .reconnecting, .filterOff,
                                        .updating, .rebootRequired, .failed("x"), .stopped]

    /// Stările cerute ca distincte au forme de simbol diferite (iconul e monocrom).
    func testDistinctShapesForDistinctStates() {
        let required: [MenuBarStatus] = [.protected, .needsApproval, .reconnecting, .filterOff, .updating, .rebootRequired, .failed("x")]
        XCTAssertEqual(Set(required.map(\.symbol)).count, required.count)
    }

    func testSymbolsExistAndTextsPresent() {
        for status in all {
            XCTAssertNotNil(NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil), status.symbol)
            XCTAssertFalse(status.text.isEmpty)
            XCTAssertTrue(status.accessibilityLabel.contains(status.text))
        }
        XCTAssertTrue(MenuBarStatus.failed("motiv").text.contains("motiv"))
    }

    func testFilteringFlag() {
        XCTAssertEqual(all.filter(\.isFiltering), [.protected, .reconnecting])
    }
}

final class DesignFoundationTests: XCTestCase {
    /// Textul colorat trece pragul WCAG AA (4.5:1) pe fundalul ferestrei, în ambele teme.
    func testColoredTextContrast() {
        for dark in [false, true] {
            let background = Contrast.resolve(.windowBackgroundColor, dark: dark)
            for tone in StatusTone.allCases where tone != .neutral {
                let ratio = Contrast.ratio(Contrast.resolve(tone.foregroundColor, dark: dark), background)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tone) \(dark ? "Dark" : "Light"): \(ratio)")
            }
        }
    }

    func testToneSymbolsDistinct() {
        XCTAssertEqual(Set(StatusTone.allCases.map(\.symbol)).count, StatusTone.allCases.count)
    }

    func testTextScaleSizes() {
        XCTAssertEqual(TextSize.allCases.map(\.scale), [1.0, 1.15, 1.3])
        XCTAssertEqual(GDCTextStyle.body.size(scale: 1), 13)
        XCTAssertEqual(GDCTextStyle.body.size(scale: 1.3), 17)
        XCTAssertEqual(GDCTextStyle.caption.size(scale: 1.15), 12)
    }

    /// Spre deosebire de `dynamicTypeSize` (fără efect pe macOS), scalarea GDC
    /// chiar mărește textul randat.
    @MainActor
    func testScaleActuallyChangesLayout() {
        _ = NSApplication.shared
        func width(_ scale: CGFloat) -> CGFloat {
            NSHostingView(rootView: Text("Protecție activă").gdcFont(.body).environment(\.gdcTextScale, scale)).fittingSize.width
        }
        XCTAssertGreaterThan(width(1.3), width(1.0) * 1.2)
    }
}

final class RuleAccessibilityTests: XCTestCase {
    override func tearDown() { UserDefaults.standard.removeObject(forKey: Lang.preferenceKey) }

    /// VoiceOver primește mereu o stare explicită, în fiecare limbă.
    func testStatesAreExplicitAndDistinct() {
        for lang in Lang.allCases {
            UserDefaults.standard.set(lang.rawValue, forKey: Lang.preferenceKey)
            let rule = [RuleAccessibility.ruleState(isDisabled: false), RuleAccessibility.ruleState(isDisabled: true)]
            let group = [RuleAccessibility.groupState(enabled: true), RuleAccessibility.groupState(enabled: false)]
            for pair in [rule, group] {
                XCTAssertFalse(pair.contains(where: \.isEmpty), "\(lang)")
                XCTAssertNotEqual(pair[0], pair[1], "\(lang)")
            }
        }
    }
}
