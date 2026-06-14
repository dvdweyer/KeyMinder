// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class ConflictDetectorTests: XCTestCase {

    private func app(_ sections: [MenuSection]) -> AppShortcuts {
        AppShortcuts(appName: "TestApp", bundleIdentifier: nil, icon: nil,
                     sections: sections, includesItemsWithoutShortcuts: false)
    }

    private func section(_ shortcuts: [Shortcut]) -> MenuSection {
        MenuSection(title: "Menu", groups: [ShortcutGroup(title: nil, shortcuts: shortcuts)])
    }

    func testNoShortcuts_noConflicts() {
        let a = app([section([])])
        XCTAssertTrue(a.conflictingKeys.isEmpty)
    }

    func testAllUnique_noConflicts() {
        let a = app([section([
            Shortcut(title: "New",  keys: "⌘N"),
            Shortcut(title: "Open", keys: "⌘O"),
            Shortcut(title: "Save", keys: "⌘S"),
        ])])
        XCTAssertTrue(a.conflictingKeys.isEmpty)
    }

    func testTwoShortcutsShareKey_bothFlagged() {
        let a = app([section([
            Shortcut(title: "New",      keys: "⌘N"),
            Shortcut(title: "Also New", keys: "⌘N"),
            Shortcut(title: "Open",     keys: "⌘O"),
        ])])
        XCTAssertEqual(a.conflictingKeys, ["⌘N"])
    }

    func testThreeShortcutsShareKey_keyFlaggedOnce() {
        let a = app([section([
            Shortcut(title: "A", keys: "⌘K"),
            Shortcut(title: "B", keys: "⌘K"),
            Shortcut(title: "C", keys: "⌘K"),
        ])])
        XCTAssertEqual(a.conflictingKeys, ["⌘K"])
    }

    func testConflictAcrossSections() {
        let s1 = section([Shortcut(title: "Cut",   keys: "⌘X")])
        let s2 = section([Shortcut(title: "Close", keys: "⌘X")])
        let a = app([s1, s2])
        XCTAssertEqual(a.conflictingKeys, ["⌘X"])
    }

    func testEmptyKeysNotFlagged() {
        // Items without a key binding (all-entries mode) must not count as conflicts,
        // even when two such items have the same empty string.
        let a = app([section([
            Shortcut(title: "No-key A", keys: ""),
            Shortcut(title: "No-key B", keys: ""),
        ])])
        XCTAssertTrue(a.conflictingKeys.isEmpty)
    }

    func testMixedEmptyAndConflicting() {
        let a = app([section([
            Shortcut(title: "No-key", keys: ""),
            Shortcut(title: "Alpha",  keys: "⌘A"),
            Shortcut(title: "Also A", keys: "⌘A"),
        ])])
        XCTAssertEqual(a.conflictingKeys, ["⌘A"])
    }
}
