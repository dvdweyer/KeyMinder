// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

/// Tests the pure per-key sync resolution helpers — no KVS or UserDefaults I/O.
final class SettingsSyncResolverTests: XCTestCase {

    // MARK: shouldApplyRemote

    func testRemoteAppliedOnlyWhenStrictlyNewer() {
        XCTAssertTrue(SettingsSync.shouldApplyRemote(kvsTs: 5, localTs: 3))
        XCTAssertTrue(SettingsSync.shouldApplyRemote(kvsTs: 1, localTs: 0))
    }

    func testRemoteNotAppliedWhenEqualOrOlder() {
        XCTAssertFalse(SettingsSync.shouldApplyRemote(kvsTs: 3, localTs: 3))
        XCTAssertFalse(SettingsSync.shouldApplyRemote(kvsTs: 2, localTs: 5))
        // Unknown provenance on both sides keeps local (the non-destructive default).
        XCTAssertFalse(SettingsSync.shouldApplyRemote(kvsTs: 0, localTs: 0))
    }

    // MARK: valuesEqual

    func testValuesEqual() {
        XCTAssertTrue(SettingsSync.valuesEqual(nil, nil))
        XCTAssertTrue(SettingsSync.valuesEqual("a" as NSString, "a" as NSString))
        XCTAssertTrue(SettingsSync.valuesEqual(true as NSNumber, true as NSNumber))
        XCTAssertTrue(SettingsSync.valuesEqual([1, 2] as NSArray, [1, 2] as NSArray))

        XCTAssertFalse(SettingsSync.valuesEqual("a" as NSString, "b" as NSString))
        XCTAssertFalse(SettingsSync.valuesEqual(nil, "a" as NSString))
        XCTAssertFalse(SettingsSync.valuesEqual("a" as NSString, nil))
        XCTAssertFalse(SettingsSync.valuesEqual([1, 2] as NSArray, [2, 1] as NSArray))
    }

    // MARK: changedKeys

    func testNoChangesWhenIdentical() {
        let snap: [String: NSObject] = ["a": "x" as NSString, "b": true as NSNumber]
        XCTAssertTrue(SettingsSync.changedKeys(current: snap, snapshot: snap).isEmpty)
    }

    func testEmptyDictsYieldNoChanges() {
        XCTAssertTrue(SettingsSync.changedKeys(current: [:], snapshot: [:]).isEmpty)
    }

    func testValueMutationDetected() {
        let snap: [String: NSObject] = ["a": "x" as NSString, "b": true as NSNumber]
        let cur:  [String: NSObject] = ["a": "y" as NSString, "b": true as NSNumber]
        XCTAssertEqual(SettingsSync.changedKeys(current: cur, snapshot: snap), ["a"])
    }

    func testAddedKeyDetected() {
        let snap: [String: NSObject] = ["a": "x" as NSString]
        let cur:  [String: NSObject] = ["a": "x" as NSString, "b": true as NSNumber]
        XCTAssertEqual(SettingsSync.changedKeys(current: cur, snapshot: snap), ["b"])
    }

    func testRemovedKeyDetected() {
        let snap: [String: NSObject] = ["a": "x" as NSString, "b": true as NSNumber]
        let cur:  [String: NSObject] = ["a": "x" as NSString]
        XCTAssertEqual(SettingsSync.changedKeys(current: cur, snapshot: snap), ["b"])
    }

    func testMultipleChangesDetected() {
        let snap: [String: NSObject] = ["a": "x" as NSString, "b": true as NSNumber, "c": [1] as NSArray]
        let cur:  [String: NSObject] = ["a": "z" as NSString, "b": true as NSNumber, "c": [1, 2] as NSArray]
        XCTAssertEqual(Set(SettingsSync.changedKeys(current: cur, snapshot: snap)), ["a", "c"])
    }
}
