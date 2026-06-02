import XCTest
@testable import KeyMinder

@MainActor
final class PopupFilterModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeShortcut(title: String, keys: String) -> Shortcut {
        Shortcut(title: title, keys: keys)
    }

    private func makeSection(_ title: String, shortcuts: [Shortcut]) -> MenuSection {
        MenuSection(title: title, groups: [ShortcutGroup(title: nil, shortcuts: shortcuts)])
    }

    private func makeModel(
        sections: [MenuSection],
        includesWithoutShortcuts: Bool = false
    ) -> PopupFilterModel {
        let app = AppShortcuts(
            appName: "TestApp",
            bundleIdentifier: nil,
            icon: nil,
            sections: sections,
            includesItemsWithoutShortcuts: includesWithoutShortcuts
        )
        let columns: [[MenuSection]] = sections.isEmpty ? [] : [sections]
        return PopupFilterModel(app: app, columns: columns)
    }

    // MARK: - visibleShortcuts

    func testVisibleShortcuts_emptyQuery_returnsAllKeyedShortcuts() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save", keys: "⌘S"),
            makeShortcut(title: "Open", keys: "⌘O"),
        ])
        let model = makeModel(sections: [section])
        XCTAssertEqual(model.visibleShortcuts.count, 2)
    }

    func testVisibleShortcuts_excludesEmptyKeys_whenShowsAllItemsFalse() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",      keys: "⌘S"),
            makeShortcut(title: "No Hotkey", keys: ""),
        ])
        // includesWithoutShortcuts=true but query is empty → activeQuery.count < 2 → showsAllItems=false
        let model = makeModel(sections: [section], includesWithoutShortcuts: true)
        XCTAssertEqual(model.visibleShortcuts.count, 1)
        XCTAssertEqual(model.visibleShortcuts[0].title, "Save")
    }

    func testVisibleShortcuts_includesMatchingEmptyKeys_whenShowsAllItemsTrue() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Export", keys: ""),    // no shortcut; matches "ex"
            makeShortcut(title: "Save",   keys: "⌘S"), // has shortcut; doesn't match "ex"
        ])
        let model = makeModel(sections: [section], includesWithoutShortcuts: true)
        model.query = "ex"  // 2 chars → showsAllItems = true
        XCTAssertEqual(model.visibleShortcuts.count, 1)
        XCTAssertEqual(model.visibleShortcuts[0].title, "Export")
    }

    func testVisibleShortcuts_whitespaceOnlyQuery_treatedAsEmpty() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",      keys: "⌘S"),
            makeShortcut(title: "No Hotkey", keys: ""),
        ])
        let model = makeModel(sections: [section], includesWithoutShortcuts: true)
        model.query = "  "  // trimmed activeQuery is empty → showsAllItems = false
        XCTAssertEqual(model.visibleShortcuts.count, 1)
    }

    func testVisibleShortcuts_updatesOnQueryChange() {
        let section = makeSection("Edit", shortcuts: [
            makeShortcut(title: "Cut",   keys: "⌘X"),
            makeShortcut(title: "Copy",  keys: "⌘C"),
            makeShortcut(title: "Paste", keys: "⌘V"),
        ])
        let model = makeModel(sections: [section])
        XCTAssertEqual(model.visibleShortcuts.count, 3)
        model.query = "cut"
        XCTAssertEqual(model.visibleShortcuts.count, 1)
        XCTAssertEqual(model.visibleShortcuts[0].title, "Cut")
    }

    // MARK: - selectNext / selectPrevious

    func testSelectNext_fromNil_selectsFirst() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "A", keys: "⌘A"),
            makeShortcut(title: "B", keys: "⌘B"),
        ])
        let model = makeModel(sections: [section])
        XCTAssertNil(model.selectedIndex)
        model.selectNext()
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testSelectNext_wrapsFromLastToFirst() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "A", keys: "⌘A"),
            makeShortcut(title: "B", keys: "⌘B"),
            makeShortcut(title: "C", keys: "⌘C"),
        ])
        let model = makeModel(sections: [section])
        model.selectedIndex = 2
        model.selectNext()
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testSelectPrevious_fromNil_selectsLast() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "A", keys: "⌘A"),
            makeShortcut(title: "B", keys: "⌘B"),
            makeShortcut(title: "C", keys: "⌘C"),
        ])
        let model = makeModel(sections: [section])
        XCTAssertNil(model.selectedIndex)
        model.selectPrevious()
        XCTAssertEqual(model.selectedIndex, 2)
    }

    func testSelectPrevious_wrapsFromFirstToLast() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "A", keys: "⌘A"),
            makeShortcut(title: "B", keys: "⌘B"),
            makeShortcut(title: "C", keys: "⌘C"),
        ])
        let model = makeModel(sections: [section])
        model.selectedIndex = 0
        model.selectPrevious()
        XCTAssertEqual(model.selectedIndex, 2)
    }

    func testSelectNext_emptyVisible_isNoOp() {
        let model = makeModel(sections: [])
        model.selectNext()
        XCTAssertNil(model.selectedIndex)
    }

    // MARK: - selectedShortcut

    func testSelectedShortcut_nilWhenNoSelection() {
        let section = makeSection("File", shortcuts: [makeShortcut(title: "A", keys: "⌘A")])
        let model = makeModel(sections: [section])
        XCTAssertNil(model.selectedShortcut)
    }

    func testSelectedShortcut_returnsCorrectItem() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "A", keys: "⌘A"),
            makeShortcut(title: "B", keys: "⌘B"),
        ])
        let model = makeModel(sections: [section])
        model.selectedIndex = 1
        XCTAssertEqual(model.selectedShortcut?.title, "B")
    }

    // MARK: - displayableCount / matchCount

    func testDisplayableCount_excludesEmptyKeys_byDefault() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",   keys: "⌘S"),
            makeShortcut(title: "Open",   keys: "⌘O"),
            makeShortcut(title: "No Key", keys: ""),
        ])
        let model = makeModel(sections: [section], includesWithoutShortcuts: true)
        // query empty → showsAllItems false → only keyed items counted
        XCTAssertEqual(model.displayableCount, 2)
    }

    func testMatchCount_withQuery() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",    keys: "⌘S"),
            makeShortcut(title: "Save As", keys: "⇧⌘S"),
            makeShortcut(title: "Open",    keys: "⌘O"),
        ])
        let model = makeModel(sections: [section])
        model.query = "save"
        XCTAssertEqual(model.matchCount, 2)
    }

    func testMatchCount_noMatch_returnsZero() {
        let section = makeSection("File", shortcuts: [makeShortcut(title: "Save", keys: "⌘S")])
        let model = makeModel(sections: [section])
        model.query = "xyz"
        XCTAssertEqual(model.matchCount, 0)
    }

    // MARK: - query change resets selectedIndex

    func testQueryChange_resetsSelectedIndex() {
        let section = makeSection("File", shortcuts: [makeShortcut(title: "Save", keys: "⌘S")])
        let model = makeModel(sections: [section])
        model.selectedIndex = 0
        model.query = "x"
        XCTAssertNil(model.selectedIndex)
    }

    func testSameQueryAssignment_doesNotResetSelectedIndex() {
        let section = makeSection("File", shortcuts: [makeShortcut(title: "Save", keys: "⌘S")])
        let model = makeModel(sections: [section])
        model.selectedIndex = 0
        model.query = ""  // same as initial value — guard oldValue != query fires
        XCTAssertEqual(model.selectedIndex, 0)
    }

    // MARK: - modifierFilter (exact-match)

    func testModifierFilter_commandOnly_showsExactMatches() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",    keys: "⌘S"),    // ⌘ only — should match
            makeShortcut(title: "Save As", keys: "⇧⌘S"),   // ⌘ + ⇧ — should not match
            makeShortcut(title: "Open",    keys: "⌘O"),    // ⌘ only — should match
            makeShortcut(title: "Undo",    keys: "⌃Z"),    // ⌃ only — should not match
        ])
        let model = makeModel(sections: [section])
        model.modifierFilter = ["⌘"]
        XCTAssertEqual(model.visibleShortcuts.map(\.title), ["Save", "Open"])
    }

    func testModifierFilter_twoModifiers_requiresBothExactly() {
        let section = makeSection("Edit", shortcuts: [
            makeShortcut(title: "Save As",     keys: "⇧⌘S"),   // exact ⇧⌘ — match
            makeShortcut(title: "Save",        keys: "⌘S"),    // ⌘ only — no match
            makeShortcut(title: "Triple",      keys: "⌃⇧⌘T"),  // three modifiers — no match
        ])
        let model = makeModel(sections: [section])
        model.modifierFilter = ["⇧", "⌘"]
        XCTAssertEqual(model.visibleShortcuts.map(\.title), ["Save As"])
    }

    func testModifierFilter_empty_showsAll() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save", keys: "⌘S"),
            makeShortcut(title: "Open", keys: "⌥⌘O"),
        ])
        let model = makeModel(sections: [section])
        model.modifierFilter = []
        XCTAssertEqual(model.visibleShortcuts.count, 2)
    }

    func testModifierFilter_resetsSelectedIndex() {
        let section = makeSection("File", shortcuts: [makeShortcut(title: "Save", keys: "⌘S")])
        let model = makeModel(sections: [section])
        model.selectedIndex = 0
        model.modifierFilter = ["⌘"]
        XCTAssertNil(model.selectedIndex)
    }

    func testModifierFilter_sameValueAssignment_doesNotResetSelectedIndex() {
        let section = makeSection("File", shortcuts: [makeShortcut(title: "Save", keys: "⌘S")])
        let model = makeModel(sections: [section])
        model.selectedIndex = 0
        model.modifierFilter = []  // same as initial — guard fires
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testMatchCount_withModifierFilter() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",    keys: "⌘S"),
            makeShortcut(title: "Save As", keys: "⇧⌘S"),
            makeShortcut(title: "Open",    keys: "⌘O"),
        ])
        let model = makeModel(sections: [section])
        model.modifierFilter = ["⌘"]
        XCTAssertEqual(model.matchCount, 2)
    }

    func testMatchCount_modifierAndTextQuery_intersects() {
        let section = makeSection("File", shortcuts: [
            makeShortcut(title: "Save",    keys: "⌘S"),
            makeShortcut(title: "Open",    keys: "⌘O"),
            makeShortcut(title: "Save As", keys: "⇧⌘S"),
        ])
        let model = makeModel(sections: [section])
        model.modifierFilter = ["⌘"]
        model.query = "save"
        XCTAssertEqual(model.matchCount, 1)
        XCTAssertEqual(model.visibleShortcuts[0].title, "Save")
    }

    func testToggleModifier_addsAndRemoves() {
        let model = makeModel(sections: [])
        XCTAssertFalse(model.hasModifierFilter)
        model.toggleModifier("⌘")
        XCTAssertTrue(model.modifierFilter.contains("⌘"))
        model.toggleModifier("⌘")
        XCTAssertFalse(model.hasModifierFilter)
    }
}
