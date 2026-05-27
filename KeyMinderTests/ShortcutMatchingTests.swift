import XCTest
@testable import KeyMinder

// MARK: - Fixture factory

private extension Shortcut {
    static func fixture(title: String, keys: String) -> Shortcut {
        Shortcut(title: title, keys: keys)
    }
}

private extension ShortcutGroup {
    static func fixture(title: String? = nil, shortcuts: [Shortcut]) -> ShortcutGroup {
        ShortcutGroup(title: title, shortcuts: shortcuts)
    }
}

private extension MenuSection {
    static func fixture(title: String, shortcuts: [Shortcut]) -> MenuSection {
        MenuSection(title: title, groups: [ShortcutGroup.fixture(shortcuts: shortcuts)])
    }
}

private extension AppShortcuts {
    static func fixture(sections: [MenuSection]) -> AppShortcuts {
        AppShortcuts(appName: "TestApp", bundleIdentifier: nil, icon: nil, sections: sections)
    }
}

// MARK: - Shortcut.matches tests

final class ShortcutMatchesTests: XCTestCase {

    // An empty query string always matches (localizedStandardContains("") is true).
    func testEmptyQuery_matchesEverything() {
        let s = Shortcut.fixture(title: "New Window", keys: "⌘N")
        XCTAssertTrue(s.matches(""))
    }

    // Title matching is case-insensitive.
    func testTitleMatch_caseInsensitive() {
        let s = Shortcut.fixture(title: "New Conversation", keys: "⇧⌘N")
        XCTAssertTrue(s.matches("new conversation"))
        XCTAssertTrue(s.matches("NEW CONVERSATION"))
        XCTAssertTrue(s.matches("Conversation"))
    }

    // Key-string matching lets users type "⌘N" or just a modifier symbol.
    func testKeyStringMatch() {
        let s = Shortcut.fixture(title: "New Window", keys: "⌘N")
        XCTAssertTrue(s.matches("⌘N"))
        XCTAssertTrue(s.matches("⌘"))   // substring of key string
    }

    // Neither title nor key string contains the query → no match.
    func testNoMatch_returnsfalse() {
        let s = Shortcut.fixture(title: "New Window", keys: "⌘N")
        XCTAssertFalse(s.matches("Paste"))
        XCTAssertFalse(s.matches("⌘V"))
    }

    // Partial title match (substring).
    func testPartialTitleMatch() {
        let s = Shortcut.fixture(title: "Find and Replace", keys: "⌥⌘F")
        XCTAssertTrue(s.matches("Replace"))
        XCTAssertTrue(s.matches("find"))   // case-insensitive substring
    }

    // Match on key string when title doesn't match.
    func testKeyOnlyMatch_titleDoesNotMatch() {
        let s = Shortcut.fixture(title: "Undo", keys: "⌘Z")
        XCTAssertFalse(s.matches("⌘N"))
        XCTAssertTrue(s.matches("⌘Z"))
    }
}

// MARK: - ShortcutGroup.hasMatch tests

final class ShortcutGroupHasMatchTests: XCTestCase {

    func testEmptyQuery_matchesAll() {
        let group = ShortcutGroup.fixture(shortcuts: [
            .fixture(title: "Cut", keys: "⌘X"),
        ])
        XCTAssertTrue(group.hasMatch(""))
    }

    func testHasMatch_whenOneShortcutMatches() {
        let group = ShortcutGroup.fixture(shortcuts: [
            .fixture(title: "Cut",   keys: "⌘X"),
            .fixture(title: "Paste", keys: "⌘V"),
        ])
        XCTAssertTrue(group.hasMatch("Cut"))
        XCTAssertTrue(group.hasMatch("Paste"))
    }

    func testHasMatch_falseWhenNoneMatch() {
        let group = ShortcutGroup.fixture(shortcuts: [
            .fixture(title: "Cut",   keys: "⌘X"),
            .fixture(title: "Paste", keys: "⌘V"),
        ])
        XCTAssertFalse(group.hasMatch("Undo"))
    }

    func testHasMatch_emptyGroup_alwaysFalseForNonEmptyQuery() {
        let group = ShortcutGroup.fixture(shortcuts: [])
        XCTAssertFalse(group.hasMatch("Cut"))
    }
}

// MARK: - MenuSection.hasMatch tests

final class MenuSectionHasMatchTests: XCTestCase {

    func testEmptyQuery_alwaysMatches() {
        let section = MenuSection.fixture(title: "Edit", shortcuts: [
            .fixture(title: "Cut", keys: "⌘X"),
        ])
        XCTAssertTrue(section.hasMatch(""))
    }

    func testHasMatch_matchingShortcutInSection() {
        let section = MenuSection.fixture(title: "File", shortcuts: [
            .fixture(title: "Save",   keys: "⌘S"),
            .fixture(title: "Export", keys: "⌘E"),
        ])
        XCTAssertTrue(section.hasMatch("Save"))
        XCTAssertTrue(section.hasMatch("export"))   // case-insensitive
    }

    func testHasMatch_matchOnKeyString() {
        let section = MenuSection.fixture(title: "Edit", shortcuts: [
            .fixture(title: "Undo", keys: "⌘Z"),
        ])
        XCTAssertTrue(section.hasMatch("⌘Z"))
    }

    func testHasMatch_noMatchInSection() {
        let section = MenuSection.fixture(title: "View", shortcuts: [
            .fixture(title: "Zoom In",  keys: "⌘+"),
            .fixture(title: "Zoom Out", keys: "⌘-"),
        ])
        XCTAssertFalse(section.hasMatch("Paste"))
    }
}

// MARK: - AppShortcuts.matchCount tests

final class AppShortcutsMatchCountTests: XCTestCase {

    private var app: AppShortcuts!

    override func setUp() {
        super.setUp()
        // Two sections, four shortcuts total.
        let edit = MenuSection.fixture(title: "Edit", shortcuts: [
            .fixture(title: "Cut",   keys: "⌘X"),
            .fixture(title: "Copy",  keys: "⌘C"),
            .fixture(title: "Paste", keys: "⌘V"),
        ])
        let file = MenuSection.fixture(title: "File", shortcuts: [
            .fixture(title: "Save", keys: "⌘S"),
        ])
        app = AppShortcuts.fixture(sections: [edit, file])
    }

    // Empty query: every shortcut matches.
    func testEmptyQuery_countEqualsTotal() {
        XCTAssertEqual(app.matchCount(""), app.totalCount)
        XCTAssertEqual(app.matchCount(""), 4)
    }

    // "C" matches "Cut", "Copy" (titles) and "⌘C" (key) → but "⌘C" is already
    // covered by "Copy". Only shortcuts where the query appears in title OR keys.
    // Cut → title "Cut" contains "C" ✓; Copy → "Copy" ✓; Paste → "Paste" ✗, "⌘V" ✗;
    // Save → "Save" ✗, "⌘S" ✗. Also ⌘C key: "Copy" has keys "⌘C" and matches "C"
    // via title already. Net: Cut + Copy = 2.
    func testCount_partialTitleQuery() {
        XCTAssertEqual(app.matchCount("Cut"), 1)
        XCTAssertEqual(app.matchCount("Copy"), 1)
    }

    // Key-string query: only the shortcut whose keys field contains "⌘S".
    func testCount_keyStringQuery() {
        XCTAssertEqual(app.matchCount("⌘S"), 1)
        XCTAssertEqual(app.matchCount("⌘X"), 1)
    }

    // No shortcut matches → 0.
    func testCount_noMatch_returnsZero() {
        XCTAssertEqual(app.matchCount("Undo"), 0)
        XCTAssertEqual(app.matchCount("⌘Z"),   0)
    }

    // All four shortcuts contain "⌘" (it appears in every key string).
    func testCount_allMatchQuery() {
        XCTAssertEqual(app.matchCount("⌘"), 4)
    }

    // matchCount of empty sections is always 0 for any non-empty query.
    func testCount_emptySections_returnsZero() {
        let empty = AppShortcuts.fixture(sections: [])
        XCTAssertEqual(empty.matchCount("anything"), 0)
    }

    // matchCount accuracy: exactly the expected number of matches.
    func testCount_accuracy_multipleMatches() {
        // "C" appears in: "Cut" (title), "Copy" (title), "⌘C" (key of Copy, but
        // Copy already counted via title). Paste has "⌘V" — no "C". Save — no "C".
        // Net: 2 matches.
        XCTAssertEqual(app.matchCount("c"), 2)
    }
}
