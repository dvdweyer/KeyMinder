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

    /// startWithLocalPriority() ("Keep Local Settings") stamps every synced key with
    /// `now`, including keys with no local value, precisely so this check rejects any
    /// remote value already in KVS at enable time — even for a key like accent colour
    /// that's locally absent (following system default) and would otherwise have
    /// localTs == 0. A future edit from another Mac, with a timestamp newer than `now`,
    /// must still be allowed through.
    func testLocalPriorityStampRejectsExistingRemoteButAllowsFutureRemote() {
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(SettingsSync.shouldApplyRemote(kvsTs: now - 100, localTs: now))
        XCTAssertFalse(SettingsSync.shouldApplyRemote(kvsTs: now, localTs: now))
        XCTAssertTrue(SettingsSync.shouldApplyRemote(kvsTs: now + 100, localTs: now))
    }

    /// push()'s local-deletion branch must compare against a fresh `now` (the deletion is
    /// happening now), not `lts[key]` (the last time this key was *synced*, which can be
    /// stale). A remote edit that landed after the key's last sync but before `now` must
    /// still lose to a deletion happening right now — only an edit *after* `now` should win.
    func testDeletionAgainstFreshNowBeatsStaleLastSyncedTimestamp() {
        let now = Date().timeIntervalSince1970
        let staleLastSynced = now - 200
        let remoteEditAfterLastSync = now - 100

        // Old (buggy) behavior: comparing against the stale last-synced timestamp, a remote
        // edit that landed after that sync but before the deletion would incorrectly win.
        XCTAssertTrue(SettingsSync.shouldApplyRemote(kvsTs: remoteEditAfterLastSync, localTs: staleLastSynced))

        // Fixed behavior: comparing against `now`, the deletion (happening now) correctly
        // beats any remote edit that landed before it.
        XCTAssertFalse(SettingsSync.shouldApplyRemote(kvsTs: remoteEditAfterLastSync, localTs: now))

        // A remote edit that lands strictly after `now` still must win.
        XCTAssertTrue(SettingsSync.shouldApplyRemote(kvsTs: now + 100, localTs: now))
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
