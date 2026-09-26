import XCTest
@testable import GDCFirewall

/// Scara de risc, Modul Silențios și catalogul de procese — logica pură din
/// spatele alertei. Textele se verifică în toate cele trei limbi.
final class RiskLevelTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Lang.preferenceKey)
    }

    func testClassificationFollowsSignatureOnly() {
        XCTAssertEqual(RiskLevel.classify(isAppleSigned: true, isNotarized: false), .appleSigned)
        XCTAssertEqual(RiskLevel.classify(isAppleSigned: true, isNotarized: true), .appleSigned)
        XCTAssertEqual(RiskLevel.classify(isAppleSigned: false, isNotarized: true), .identifiedDeveloper)
        XCTAssertEqual(RiskLevel.classify(isAppleSigned: false, isNotarized: false), .unverified)
    }

    func testConnectionRequestMapsEngineSigner() {
        XCTAssertEqual(Fixtures.request(signer: LuLu.Signer.apple).risk, .appleSigned)
        XCTAssertEqual(Fixtures.request(signer: LuLu.Signer.devID).risk, .identifiedDeveloper)
        XCTAssertEqual(Fixtures.request(signer: LuLu.Signer.appStore).risk, .identifiedDeveloper)
        XCTAssertEqual(Fixtures.request(signer: LuLu.Signer.none).risk, .unverified)
        XCTAssertEqual(Fixtures.request(signer: 4 /* AdHoc */).risk, .unverified)
    }

    /// Portul se scrie ca număr brut, fără separatorul de mii al limbii („8.080”).
    func testPortHasNoLocaleGrouping() {
        for lang in Lang.allCases {
            UserDefaults.standard.set(lang.rawValue, forKey: Lang.preferenceKey)
            XCTAssertTrue(Fixtures.request(port: "8080").portDescription.hasSuffix(" 8080"), "\(lang)")
        }
    }

    /// Acțiunea implicită a alertei e NESCHIMBATĂ față de 2.3.5: doar Apple → Permite.
    func testDefaultActionUnchanged() {
        XCTAssertTrue(RiskLevel.appleSigned.defaultsToAllow)
        XCTAssertFalse(RiskLevel.identifiedDeveloper.defaultsToAllow)
        XCTAssertFalse(RiskLevel.unverified.defaultsToAllow)
    }

    func testTonesAreDistinctAndOrdered() {
        XCTAssertEqual(RiskLevel.allCases.map(\.tone), [.success, .attention, .error])
        XCTAssertEqual(Set(RiskLevel.allCases.map(\.systemImage)).count, 3)
        XCTAssertLessThan(RiskLevel.appleSigned, RiskLevel.unverified)
    }

    /// Faptul, estimarea, explicația și recomandarea sunt texte distincte, în
    /// fiecare limbă, și niciunul nu afirmă că programul „e sigur”.
    func testSemanticTextsInAllLanguages() {
        let forbidden = ["sigur", "safe", "seguro"]
        for lang in Lang.allCases {
            UserDefaults.standard.set(lang.rawValue, forKey: Lang.preferenceKey)
            for level in RiskLevel.allCases {
                let texts = [level.identity, level.assessment, level.explanation, level.recommendation]
                XCTAssertEqual(Set(texts).count, 4, "\(lang) \(level): texte repetate")
                XCTAssertFalse(texts.contains(where: \.isEmpty))
                XCTAssertFalse(level.identity.split(separator: " ").contains { forbidden.contains($0.lowercased()) },
                               "\(lang) \(level): identitatea conține un verdict")
            }
            if lang != .ro {
                XCTAssertNotEqual(RiskLevel.unverified.identity, "Semnătură lipsă sau invalidă", "\(lang) netradus")
            }
        }
        UserDefaults.standard.set("ro", forKey: Lang.preferenceKey)
        XCTAssertEqual(RiskLevel.appleSigned.identity, "Componentă macOS semnată de Apple")
        XCTAssertEqual(RiskLevel.identifiedDeveloper.identity, "Dezvoltator identificat")
        XCTAssertEqual(RiskLevel.unverified.identity, "Semnătură lipsă sau invalidă")
    }
}

final class AutoPilotTests: XCTestCase {
    private let pilot = AutoPilot.shared

    func testApproveAppleSignedAppleBundle() {
        XCTAssertTrue(pilot.qualifies(Fixtures.request(path: "/System/Applications/Mail.app/Contents/MacOS/Mail",
                                                       signingID: "com.apple.mail", signer: LuLu.Signer.apple)))
    }

    /// Un bundle ID `com.apple.*` scris în propriul Info.plist nu e suficient.
    func testRejectSpoofedAppleBundleID() {
        XCTAssertFalse(pilot.qualifies(Fixtures.request(signingID: "com.apple.fake", signer: LuLu.Signer.devID)))
        XCTAssertFalse(pilot.qualifies(Fixtures.request(signingID: "com.apple.fake", signer: LuLu.Signer.none)))
    }

    func testRejectAppleSignedNonAppleBundle() {
        XCTAssertFalse(pilot.qualifies(Fixtures.request(signingID: "us.zoom.xos", signer: LuLu.Signer.apple)))
    }

    func testSystemDaemonWithoutBundleIDOnlyFromSystemLocations() {
        for path in ["/usr/libexec/trustd", "/System/Library/X/y", "/usr/sbin/mDNSResponder"] {
            XCTAssertTrue(pilot.qualifies(Fixtures.request(path: path, signingID: nil, signer: LuLu.Signer.apple)), path)
        }
        for path in ["/usr/local/bin/tool", "/Users/test/tool", "/Applications/X.app/Contents/MacOS/X"] {
            XCTAssertFalse(pilot.qualifies(Fixtures.request(path: path, signingID: nil, signer: LuLu.Signer.apple)), path)
        }
    }
}

final class ProcessCatalogTests: XCTestCase {
    private let catalog = ProcessCatalog.shared

    func testLookupByProcessName() {
        XCTAssertEqual(catalog.lookup(processName: "nsurlsessiond")?.name, "Descărcări în fundal macOS")
    }

    func testLookupByFullBundleID() {
        XCTAssertEqual(catalog.lookup(processName: "geod-x", bundleID: "com.apple.geod")?.name, "Servicii de localizare Apple")
    }

    func testLookupByLastBundleSegment() {
        XCTAssertEqual(catalog.lookup(processName: "other", bundleID: "com.example.nsurlsessiond")?.name, "Descărcări în fundal macOS")
    }

    func testUnknownReturnsNilAndFriendlyNameFallsBack() {
        XCTAssertNil(catalog.lookup(processName: "no-such-process", bundleID: "com.example.nothing"))
        XCTAssertEqual(catalog.friendlyName(processName: "tool", bundleID: nil, displayName: "Tool App"), "Tool App")
        XCTAssertEqual(catalog.friendlyName(processName: "tool", bundleID: nil, displayName: nil), "tool")
        XCTAssertNil(catalog.detail(processName: "tool", bundleID: nil))
    }
}

final class RuleAnalysisTests: XCTestCase {
    private let old = Date(timeIntervalSince1970: 1_000_000)

    func testActiveExcludesDisabledAndExpired() {
        let on = Fixtures.rule()
        let off = Fixtures.rule(disabled: true)
        let expired = Fixtures.rule(expires: Date().addingTimeInterval(-60))
        let result = RuleAnalysis.rules(for: .active, in: [on, off, expired], mismatches: [])
        XCTAssertEqual(result.map(\.id), [on.id])
    }

    func testDenyTemporaryUnapprovedExpired() {
        let block = Fixtures.rule(action: .block)
        let temp = Fixtures.rule(pid: 12)
        let passive = Fixtures.rule(kind: .passive)
        let expired = Fixtures.rule(expires: Date().addingTimeInterval(-60))
        let all = [block, temp, passive, expired]
        XCTAssertEqual(RuleAnalysis.rules(for: .deny, in: all, mismatches: []).map(\.id), [block.id])
        XCTAssertEqual(RuleAnalysis.rules(for: .temporary, in: all, mismatches: []).map(\.id), [temp.id])
        XCTAssertEqual(RuleAnalysis.rules(for: .unapproved, in: all, mismatches: []).map(\.id), [passive.id])
        XCTAssertEqual(RuleAnalysis.rules(for: .expired, in: all, mismatches: []).map(\.id), [expired.id])
    }

    /// Prima regulă rămâne; copiile identice (cale, destinație, port, acțiune) sunt redundante.
    func testRedundantKeepsOldest() {
        let first = Fixtures.rule(addr: "a.com", port: "443", created: old)
        let copy = Fixtures.rule(addr: "a.com", port: "443", created: old.addingTimeInterval(10))
        let otherPort = Fixtures.rule(addr: "a.com", port: "80", created: old.addingTimeInterval(20))
        let otherAction = Fixtures.rule(addr: "a.com", port: "443", action: .block, created: old.addingTimeInterval(30))
        let result = RuleAnalysis.redundant(in: [copy, otherAction, first, otherPort])
        XCTAssertEqual(result.map(\.id), [copy.id])
    }

    func testRecentChangesWindowAndOrder() {
        let recent = Fixtures.rule(created: Date().addingTimeInterval(-3600))
        let newest = Fixtures.rule(created: Date().addingTimeInterval(-60))
        let stale = Fixtures.rule(created: old)
        let result = RuleAnalysis.rules(for: .recentChanges, in: [recent, stale, newest], mismatches: [])
        XCTAssertEqual(result.map(\.id), [newest.id, recent.id])
    }

    func testIdentityAndExecutableChecks() {
        let missing = Fixtures.rule(path: "/nonexistent/\(UUID().uuidString)/tool")
        let unsigned = Fixtures.rule(path: "/bin/ls")
        let signed = Fixtures.rule(path: "/bin/ls", signingID: "com.apple.ls")
        let global = Fixtures.rule(path: "*")
        let all = [missing, unsigned, signed, global]
        XCTAssertEqual(RuleAnalysis.rules(for: .missingExecutable, in: all, mismatches: []).map(\.id), [missing.id])
        XCTAssertEqual(RuleAnalysis.rules(for: .noIdentityCheck, in: all, mismatches: []).map(\.id), [unsigned.id])
        XCTAssertEqual(RuleAnalysis.rules(for: .identityMismatch, in: all, mismatches: [signed.id]).map(\.id), [signed.id])
        XCTAssertTrue(RuleAnalysis.rules(for: .blocklist, in: all, mismatches: []).isEmpty)
    }

    func testIdentityMatchIgnoresAppleTeam() {
        let rule = Fixtures.rule(signingID: "com.example.app")
        XCTAssertTrue(IdentityChecker.matches(rule: rule, current: .init(codeID: "com.example.app", teamID: "ABC")))
        XCTAssertFalse(IdentityChecker.matches(rule: rule, current: .init(codeID: "com.other.app", teamID: "ABC")))
    }
}
