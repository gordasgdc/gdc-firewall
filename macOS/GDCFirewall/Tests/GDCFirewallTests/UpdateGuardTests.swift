import XCTest
@testable import GDCFirewall

/// Motor simulat: ține preferințele în memorie, ca daemon-ul LuLu, și răspunde
/// la `updatePreferences` cu preferințele de după aplicare.
@MainActor
private final class FakeEngine: UpdateGuardEngine {
    var isConnected = true
    var prefs: [String: Any] = [:]
    var applied: [[String: Any]] = []

    func preferences() async -> [String: Any]? { isConnected ? prefs : nil }

    func applyPreferences(_ preferences: [String: Any]) async -> [String: Any]? {
        guard isConnected else { return nil }
        prefs.merge(preferences) { _, new in new }
        applied.append(preferences)
        return prefs
    }
}

@MainActor
final class UpdateGuardTests: XCTestCase {
    private var engine: FakeEngine!
    private var defaults: UserDefaults!
    private var suite: String!
    private var updating = false

    override func setUp() async throws {
        suite = "UpdateGuardTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        engine = FakeEngine()
        updating = false
        UpdateGuard.engine = engine
        UpdateGuard.defaults = defaults
        UpdateGuard.updateInProgress = { [unowned self] in self.updating }
        UpdateGuard.connectPollInterval = 1_000_000
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private var passiveMode: Bool { engine.prefs[LuLu.Pref.passiveMode] as? Bool ?? false }
    private var engineInGuard: Bool { UpdateGuard.isGuard(UpdateGuard.passiveTriple(engine.prefs)) }

    func testEngageThenReleaseRestoresPrevious() async {
        engine.prefs = UpdateGuard.normalPrefs
        let engaged = await UpdateGuard.engage(timeout: 0.01)
        XCTAssertTrue(engaged)
        XCTAssertTrue(engineInGuard)
        let released = await UpdateGuard.release()
        XCTAssertTrue(released)
        XCTAssertFalse(passiveMode)
        XCTAssertFalse(UpdateGuard.isEngaged)
    }

    /// Bug-ul confirmat în log: ridicare cu motorul neconectat.
    func testReleaseWhileDisconnectedKeepsStateAndRetriesOnConnect() async {
        engine.prefs = UpdateGuard.normalPrefs
        await UpdateGuard.engage(timeout: 0.01)
        engine.isConnected = false
        let released = await UpdateGuard.release()
        XCTAssertFalse(released)
        XCTAssertTrue(UpdateGuard.isEngaged, "copia salvată nu se pierde fără confirmarea motorului")
        XCTAssertEqual(UpdateGuard.state, .releasing)

        // Ridicarea cerută se reia la conectare, chiar dacă etapa nu e .idle (amânare).
        updating = true
        engine.isConnected = true
        await UpdateGuard.releaseIfSafe()
        XCTAssertFalse(passiveMode)
        XCTAssertFalse(UpdateGuard.isEngaged)
    }

    /// Secvența din log: ridicare pierdută, apoi o nouă gardă.
    func testSecondEngageAfterLostReleaseNeverSnapshotsGuardState() async {
        engine.prefs = UpdateGuard.normalPrefs
        await UpdateGuard.engage(timeout: 0.01)
        engine.isConnected = false
        await UpdateGuard.release()
        engine.isConnected = true
        await UpdateGuard.engage(timeout: 0.01)
        await UpdateGuard.release()
        XCTAssertFalse(passiveMode)
        XCTAssertFalse(UpdateGuard.isEngaged)
    }

    func testDoubleEngageKeepsOriginalSnapshot() async {
        engine.prefs = UpdateGuard.normalPrefs
        await UpdateGuard.engage(timeout: 0.01)
        await UpdateGuard.engage(timeout: 0.01)
        await UpdateGuard.release()
        XCTAssertFalse(passiveMode)
    }

    /// Motor deja în starea gardei, fără copie salvată (starea Mac-ului de dezvoltare).
    func testEngageOnStuckGuardSavesNormalMode() async {
        engine.prefs = UpdateGuard.guardPrefs
        await UpdateGuard.engage(timeout: 0.01)
        await UpdateGuard.release()
        XCTAssertFalse(passiveMode)
    }

    /// Copia „otrăvită” lăsată de 2.3.4 (doar cheia veche, cu starea gardei).
    func testLegacyPoisonedSnapshotRestoresNormalMode() async {
        engine.prefs = UpdateGuard.guardPrefs
        defaults.set(UpdateGuard.guardPrefs, forKey: UpdateGuard.savedKey)
        XCTAssertTrue(UpdateGuard.isEngaged)
        await UpdateGuard.releaseIfSafe()
        XCTAssertFalse(passiveMode)
        XCTAssertFalse(UpdateGuard.isEngaged)
    }

    func testReleaseIfSafeWaitsDuringUpdate() async {
        engine.prefs = UpdateGuard.normalPrefs
        await UpdateGuard.engage(timeout: 0.01)
        updating = true
        await UpdateGuard.releaseIfSafe()
        XCTAssertTrue(engineInGuard, "cu înlocuirea în curs garda rămâne")
        updating = false
        await UpdateGuard.releaseIfSafe()
        XCTAssertFalse(passiveMode)
    }

    func testStartupSelfHealWhenIdle() async {
        engine.prefs = UpdateGuard.guardPrefs
        await UpdateGuard.releaseIfSafe()
        XCTAssertFalse(passiveMode)
    }

    func testNoSelfHealDuringUpdate() async {
        engine.prefs = UpdateGuard.guardPrefs
        updating = true
        await UpdateGuard.releaseIfSafe()
        XCTAssertTrue(engineInGuard)
    }

    /// Un mod pasiv ales de utilizator (ex. „permite”) nu e atins.
    func testUserPassiveAllowIsPreserved() async {
        let userPrefs: [String: Any] = [
            LuLu.Pref.passiveMode: true,
            LuLu.Pref.passiveModeAction: LuLu.Pref.passiveAllow,
            LuLu.Pref.passiveModeRules: 1,
        ]
        engine.prefs = userPrefs
        await UpdateGuard.releaseIfSafe()
        XCTAssertTrue(engine.applied.isEmpty)
        await UpdateGuard.engage(timeout: 0.01)
        await UpdateGuard.release()
        XCTAssertTrue(passiveMode)
        XCTAssertEqual(engine.prefs[LuLu.Pref.passiveModeRules] as? Int, 1)
    }

    func testEngageFailsWhenDisconnected() async {
        engine.isConnected = false
        let engaged = await UpdateGuard.engage(timeout: 0.01)
        XCTAssertFalse(engaged)
        XCTAssertFalse(UpdateGuard.isEngaged)
    }

    // MARK: - Cursa Self-Updater: conectare la motorul VECHI la pornire

    func testForeignEngineDetection() {
        let prefix = EngineService.labelPrefix
        let new = prefix + "2.3.5.9", old = prefix + "2.3.4.8"
        XCTAssertTrue(EngineService.isForeignEngine(running: [old], bundled: new))
        XCTAssertTrue(EngineService.isForeignEngine(running: [old, new], bundled: new))
        XCTAssertFalse(EngineService.isForeignEngine(running: [new], bundled: new))
        XCTAssertFalse(EngineService.isForeignEngine(running: [], bundled: new), "citire eșuată: nu blocăm garda")
        XCTAssertFalse(EngineService.isForeignEngine(running: [old], bundled: nil), "harnașamentul SPM")
    }

    /// Aplicația nouă pornește, se conectează la extensia veche înainte de
    /// `.replacing`: garda setată de Self-Updater rămâne; se ridică doar după
    /// ce rulează extensia din pachet.
    func testGuardHeldWhileOldEngineRunsAfterSelfUpdate() async {
        engine.prefs = UpdateGuard.normalPrefs
        await UpdateGuard.engage(timeout: 0.01)        // aplicația veche, înainte de instalare
        updating = true                                 // extensia veche încă rulează
        await UpdateGuard.releaseIfSafe()               // checkIn al aplicației noi
        XCTAssertTrue(engineInGuard)
        XCTAssertEqual(UpdateGuard.state, .engaged)
        updating = false                                // extensia nouă a înlocuit-o
        await UpdateGuard.releaseIfSafe()
        XCTAssertFalse(passiveMode)
        XCTAssertFalse(UpdateGuard.isEngaged)
    }

    /// Regulile utilizatorului nu trec niciodată prin gardă: doar cele 3 chei ale modului pasiv.
    func testOnlyPassiveKeysAreSent() async {
        engine.prefs = UpdateGuard.normalPrefs
        engine.prefs["useBlockList"] = true
        await UpdateGuard.engage(timeout: 0.01)
        await UpdateGuard.release()
        let keys = Set(engine.applied.flatMap { $0.keys })
        XCTAssertEqual(keys, [LuLu.Pref.passiveMode, LuLu.Pref.passiveModeAction, LuLu.Pref.passiveModeRules])
        XCTAssertEqual(engine.prefs["useBlockList"] as? Bool, true)
    }
}
