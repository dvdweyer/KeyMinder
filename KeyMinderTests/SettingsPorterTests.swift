// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class SettingsPorterTests: XCTestCase {

    // Keys used as test fixtures — boolean, no side effects when toggled in a test process.
    private let keyA = "debugLoggingEnabled"
    private let keyB = "wrapLongSections"
    private let keyC = "showConflictIndicator"

    // Isolated UserDefaults suite — SettingsPorter.apply() has full-replace semantics
    // (it removes every known key absent from the import), so it must never run against
    // .standard: xcodebuild test hosts this bundle inside the real KeyMinder.app process,
    // meaning .standard IS the user's real ~/Library/Preferences/org.afaik.KeyMinder.plist.
    private var defaults: UserDefaults!
    private static let suiteName = "org.afaik.KeyMinder.SettingsPorterTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Round-trip

    func testRoundTrip_writtenValuesAreRestored() throws {
        defaults.set(true,  forKey: keyA)
        defaults.set(false, forKey: keyB)

        let data = try SettingsPorter.export(defaults: defaults)

        defaults.removeObject(forKey: keyA)
        defaults.removeObject(forKey: keyB)

        try SettingsPorter.apply(data, defaults: defaults)

        XCTAssertEqual(defaults.bool(forKey: keyA), true)
        XCTAssertEqual(defaults.bool(forKey: keyB), false)
    }

    func testRoundTrip_metadataKeysDoNotLeakIntoDefaults() throws {
        let data = try SettingsPorter.export(defaults: defaults)
        try SettingsPorter.apply(data, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "__version"))
        XCTAssertNil(defaults.object(forKey: "__exportedAt"))
        XCTAssertNil(defaults.object(forKey: "__keyminderVersion"))
    }

    // MARK: - Absent-key removal

    func testApply_removesKeyAbsentInExport() throws {
        // Export while keyC is absent — so it won't appear in the export dict.
        let data = try SettingsPorter.export(defaults: defaults)

        // Now set keyC, simulating a key that existed before the import.
        defaults.set(true, forKey: keyC)

        try SettingsPorter.apply(data, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: keyC))
    }

    // MARK: - Error paths

    func testApply_corruptData_throws() {
        // PropertyListSerialization throws .propertyListReadCorrupt (3840) for garbage bytes.
        XCTAssertThrowsError(try SettingsPorter.apply(Data("not a plist".utf8), defaults: defaults)) { error in
            XCTAssertNotNil(error as? CocoaError)
        }
    }

    func testApply_validPlistButWrongRootType_throwsCocoaError() throws {
        let arrayData = try PropertyListSerialization.data(
            fromPropertyList: ["a", "b"], format: .xml, options: 0)
        XCTAssertThrowsError(try SettingsPorter.apply(arrayData, defaults: defaults)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
    }

    // MARK: - Empty dictionary

    func testExport_emptyDefaults_producesValidPlist() throws {
        let data = try SettingsPorter.export(defaults: defaults)
        let dict = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        for key in SettingsPorter.keys {
            XCTAssertNil(dict[key], "Expected no value for absent key '\(key)'")
        }
    }

    func testApply_emptyDict_removesAllKnownKeys() throws {
        defaults.set(true, forKey: keyA)
        defaults.set(true, forKey: keyB)

        let emptyExport = try PropertyListSerialization.data(
            fromPropertyList: ["__version": 1, "__exportedAt": "", "__keyminderVersion": ""],
            format: .xml, options: 0)

        try SettingsPorter.apply(emptyExport, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: keyA))
        XCTAssertNil(defaults.object(forKey: keyB))
    }

    // MARK: - Smoke test

    func testExport_doesNotThrow() throws {
        let data = try SettingsPorter.export(defaults: defaults)
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Keys list invariants

    func testKeys_hasExpectedCount() {
        XCTAssertEqual(SettingsPorter.keys.count, 25)
    }

    func testKeys_hasNoDuplicates() {
        XCTAssertEqual(SettingsPorter.keys.count, Set(SettingsPorter.keys).count)
    }

    func testKeys_containsKnownEntries() {
        XCTAssertTrue(SettingsPorter.keys.contains("globalHotkey"))
        XCTAssertTrue(SettingsPorter.keys.contains("debugLoggingEnabled"))
        XCTAssertTrue(SettingsPorter.keys.contains("pinnedShortcuts"))
    }
}
