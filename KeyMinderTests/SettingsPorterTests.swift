// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class SettingsPorterTests: XCTestCase {

    // Keys used as test fixtures — boolean, no side effects when toggled in a test process.
    private let keyA = "debugLoggingEnabled"
    private let keyB = "wrapLongSections"
    private let keyC = "showConflictIndicator"

    // Saved originals, restored in tearDown so tests don't pollute real prefs.
    private var savedValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        let fixtureKeys = [keyA, keyB, keyC]
        for key in fixtureKeys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in savedValues {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedValues = [:]
        super.tearDown()
    }

    // MARK: - Round-trip

    func testRoundTrip_writtenValuesAreRestored() throws {
        UserDefaults.standard.set(true,  forKey: keyA)
        UserDefaults.standard.set(false, forKey: keyB)

        let data = try SettingsPorter.export()

        UserDefaults.standard.removeObject(forKey: keyA)
        UserDefaults.standard.removeObject(forKey: keyB)

        try SettingsPorter.apply(data)

        XCTAssertEqual(UserDefaults.standard.bool(forKey: keyA), true)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: keyB), false)
    }

    func testRoundTrip_metadataKeysDoNotLeakIntoDefaults() throws {
        let data = try SettingsPorter.export()
        try SettingsPorter.apply(data)

        XCTAssertNil(UserDefaults.standard.object(forKey: "__version"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "__exportedAt"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "__keyminderVersion"))
    }

    // MARK: - Absent-key removal

    func testApply_removesKeyAbsentInExport() throws {
        // Export while keyC is absent — so it won't appear in the export dict.
        let data = try SettingsPorter.export()

        // Now set keyC, simulating a key that existed before the import.
        UserDefaults.standard.set(true, forKey: keyC)

        try SettingsPorter.apply(data)

        XCTAssertNil(UserDefaults.standard.object(forKey: keyC))
    }

    // MARK: - Error paths

    func testApply_corruptData_throws() {
        // PropertyListSerialization throws .propertyListReadCorrupt (3840) for garbage bytes.
        XCTAssertThrowsError(try SettingsPorter.apply(Data("not a plist".utf8))) { error in
            XCTAssertNotNil(error as? CocoaError)
        }
    }

    func testApply_validPlistButWrongRootType_throwsCocoaError() throws {
        let arrayData = try PropertyListSerialization.data(
            fromPropertyList: ["a", "b"], format: .xml, options: 0)
        XCTAssertThrowsError(try SettingsPorter.apply(arrayData)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
    }

    // MARK: - Empty dictionary

    func testExport_emptyDefaults_producesValidPlist() throws {
        let data = try SettingsPorter.export()
        let dict = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        for key in SettingsPorter.keys {
            XCTAssertNil(dict[key], "Expected no value for absent key '\(key)'")
        }
    }

    func testApply_emptyDict_removesAllKnownKeys() throws {
        UserDefaults.standard.set(true, forKey: keyA)
        UserDefaults.standard.set(true, forKey: keyB)

        let emptyExport = try PropertyListSerialization.data(
            fromPropertyList: ["__version": 1, "__exportedAt": "", "__keyminderVersion": ""],
            format: .xml, options: 0)

        try SettingsPorter.apply(emptyExport)

        XCTAssertNil(UserDefaults.standard.object(forKey: keyA))
        XCTAssertNil(UserDefaults.standard.object(forKey: keyB))
    }

    // MARK: - Smoke test

    func testExport_doesNotThrow() throws {
        let data = try SettingsPorter.export()
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Keys list invariants

    func testKeys_hasExpectedCount() {
        XCTAssertEqual(SettingsPorter.keys.count, 24)
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
