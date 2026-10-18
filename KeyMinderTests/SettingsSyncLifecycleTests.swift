// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

/// In-memory stand-in for NSUbiquitousKeyValueStore, so tests never touch the real
/// iCloud-backed store.
private final class FakeKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
    func set(_ value: Double, forKey key: String) { storage[key] = value }
    func double(forKey key: String) -> Double { (storage[key] as? Double) ?? 0 }
    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
    func synchronize() -> Bool { true }
}

/// Exercises SettingsSync's stateful lifecycle (start/push/pull/observe) against a
/// fake KVS and a private UserDefaults suite — never the real iCloud store or
/// `.standard`, which under `xcodebuild test` is the user's actual preferences domain
/// (see SettingsPorterTests and the 2026-07-12 settings-reset incident).
@MainActor
final class SettingsSyncLifecycleTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "org.afaik.KeyMinder.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeSync(kvs: FakeKeyValueStore = FakeKeyValueStore()) -> (SettingsSync, FakeKeyValueStore) {
        (SettingsSync(kvs: kvs, defaults: defaults), kvs)
    }

    // MARK: Enable → push → pull round-trip

    func testLocalEditPushesToKVSAndRemoteEditPullsToLocal() {
        let (macA, sharedKVS) = makeSync()
        macA.start()

        // An edit made after sync is live is debounced; flush() (also covered on its
        // own below) lets the test push it without waiting out the real 1s debounce.
        defaults.set(true, forKey: "showAllMenuItems")
        macA.flush()
        XCTAssertEqual(sharedKVS.object(forKey: "showAllMenuItems") as? Bool, true)

        // A second Mac, pointed at the same KVS, pulls what the first pushed.
        let macBSuiteName = "org.afaik.KeyMinder.tests.\(UUID().uuidString)"
        let macBDefaults = UserDefaults(suiteName: macBSuiteName)!
        defer { macBDefaults.removePersistentDomain(forName: macBSuiteName) }
        let macB = SettingsSync(kvs: sharedKVS, defaults: macBDefaults)
        macB.start()
        XCTAssertEqual(macBDefaults.bool(forKey: "showAllMenuItems"), true)
    }

    // MARK: Quit mid-debounce (v1.0.209 flush fix)

    func testFlushPushesAChangeStillWaitingOutTheDebounce() {
        let (sync, kvs) = makeSync()
        sync.start()
        defaults.set(true, forKey: "wrapLongSections")
        sync.flush()
        XCTAssertEqual(kvs.object(forKey: "wrapLongSections") as? Bool, true,
                       "flush() must push a pending edit immediately, as applicationWillTerminate does before quitting")
    }

    // MARK: Edit while sync off → re-enable (v1.0.210 fix)

    func testEditWhileStoppedIsPushedOnRestart() {
        let (sync, kvs) = makeSync()
        sync.start()
        sync.stop()
        defaults.set(true, forKey: "showConflictIndicator")
        // No debounce observer is active while stopped; the edit must still reach
        // KVS the next time sync starts, not be silently lost.
        sync.start()
        XCTAssertEqual(kvs.object(forKey: "showConflictIndicator") as? Bool, true,
                       "an edit made while sync was off must be pushed when sync restarts")
    }

    // MARK: First-enable conflict paths

    func testWouldApplyRemoteDetectsANewerRemoteValue() {
        let (sync, kvs) = makeSync()
        kvs.set(true as NSNumber, forKey: "showSystemShortcuts")
        kvs.set(Date().timeIntervalSince1970, forKey: "__ts_showSystemShortcuts")
        XCTAssertTrue(sync.wouldApplyRemote(),
                      "a KVS value with no matching local timestamp on record should be seen as pullable")
    }

    func testConfirmICloudWithRemoteAdoptsTheRemoteValue() {
        let (sync, kvs) = makeSync()
        defaults.set(false, forKey: "showSystemShortcuts")
        kvs.set(true as NSNumber, forKey: "showSystemShortcuts")
        kvs.set(Date().timeIntervalSince1970, forKey: "__ts_showSystemShortcuts")
        sync.start() // "Use iCloud Settings" path: start() always pulls a newer remote value
        XCTAssertEqual(defaults.bool(forKey: "showSystemShortcuts"), true)
    }

    func testStartWithLocalPriorityKeepsLocalOverAnExistingRemoteValue() {
        let (sync, kvs) = makeSync()
        defaults.set(false, forKey: "showSystemShortcuts")
        kvs.set(true as NSNumber, forKey: "showSystemShortcuts")
        kvs.set(Date().timeIntervalSince1970, forKey: "__ts_showSystemShortcuts")
        sync.startWithLocalPriority() // "Keep Local Settings" path
        XCTAssertEqual(defaults.bool(forKey: "showSystemShortcuts"), false)
        XCTAssertEqual(kvs.object(forKey: "showSystemShortcuts") as? NSNumber, false,
                       "keeping local settings must also overwrite the remote value, not just skip pulling it")
    }
}
