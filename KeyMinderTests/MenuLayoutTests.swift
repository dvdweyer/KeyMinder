import XCTest
@testable import KeyMinder

// MARK: - Fixture factory

/// Builds MenuSection values without needing real scraped data.
private extension MenuSection {

    /// Creates a MenuSection with the given title and groups.
    /// Each element of `groups` is a (submenu-title-or-nil, shortcut-count) pair.
    static func fixture(title: String, groups: [(String?, Int)]) -> MenuSection {
        let shortcutGroups = groups.map { (groupTitle, count) in
            ShortcutGroup(
                title: groupTitle,
                shortcuts: (0..<count).map { i in Shortcut(title: "Item \(i)", keys: "⌘\(i)") }
            )
        }
        return MenuSection(title: title, groups: shortcutGroups)
    }

    /// Convenience: one unnamed group with `count` shortcuts.
    static func fixture(title: String, count: Int) -> MenuSection {
        .fixture(title: title, groups: [(nil, count)])
    }
}

// MARK: - MenuLayout.height(of:) tests

final class MenuLayoutHeightTests: XCTestCase {

    func testHeight_noGroups_equalsHeaderOnly() {
        // elementCount = 1, gaps = 0 → just the header height
        let section = MenuSection.fixture(title: "Empty", groups: [])
        XCTAssertEqual(MenuLayout.height(of: section),
                       MenuLayout.headerHeight,
                       accuracy: 0.001)
    }

    func testHeight_singleUnnamedGroup_threeShortcuts() {
        // elementCount = 1 header + 0 subheaders + 3 rows = 4 → gaps = 3
        let section = MenuSection.fixture(title: "File", count: 3)
        let expected = MenuLayout.headerHeight
            + 3 * MenuLayout.rowHeight
            + 3 * MenuLayout.rowSpacing
        XCTAssertEqual(MenuLayout.height(of: section), expected, accuracy: 0.001)
    }

    func testHeight_oneNamedGroup() {
        // elementCount = 1 + 1 subheader + 2 rows = 4 → gaps = 3
        let section = MenuSection.fixture(title: "Edit", groups: [("Sub", 2)])
        let expected = MenuLayout.headerHeight
            + 1 * MenuLayout.subGroupHeaderHeight
            + 2 * MenuLayout.rowHeight
            + 3 * MenuLayout.rowSpacing
        XCTAssertEqual(MenuLayout.height(of: section), expected, accuracy: 0.001)
    }

    func testHeight_mixedGroups() {
        // groups: unnamed with 2, named with 3
        // namedGroupCount=1, totalShortcuts=5, elementCount=7, gaps=6
        let section = MenuSection.fixture(title: "View", groups: [(nil, 2), ("Layout", 3)])
        let expected = MenuLayout.headerHeight
            + 1 * MenuLayout.subGroupHeaderHeight
            + 5 * MenuLayout.rowHeight
            + 6 * MenuLayout.rowSpacing
        XCTAssertEqual(MenuLayout.height(of: section), expected, accuracy: 0.001)
    }

    func testHeight_twoNamedGroups() {
        // namedGroupCount=2, totalShortcuts=4, elementCount=7, gaps=6
        let section = MenuSection.fixture(title: "Window", groups: [("A", 2), ("B", 2)])
        let expected = MenuLayout.headerHeight
            + 2 * MenuLayout.subGroupHeaderHeight
            + 4 * MenuLayout.rowHeight
            + 6 * MenuLayout.rowSpacing
        XCTAssertEqual(MenuLayout.height(of: section), expected, accuracy: 0.001)
    }

    func testHeight_singleShortcut() {
        // elementCount = 2, gaps = 1
        let section = MenuSection.fixture(title: "Help", count: 1)
        let expected = MenuLayout.headerHeight
            + 1 * MenuLayout.rowHeight
            + 1 * MenuLayout.rowSpacing
        XCTAssertEqual(MenuLayout.height(of: section), expected, accuracy: 0.001)
    }
}

// MARK: - MenuLayout.distribute(_:columns:) tests

final class MenuLayoutDistributeTests: XCTestCase {

    // MARK: Edge cases

    func testDistribute_emptyInput_returnsEmpty() {
        XCTAssertTrue(MenuLayout.distribute([], columns: 3).isEmpty)
    }

    func testDistribute_singleSection_singleColumn_returnsSingleSlice() {
        let sections = [MenuSection.fixture(title: "File", count: 5)]
        let result = MenuLayout.distribute(sections, columns: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].count, 1)
    }

    func testDistribute_columnsEqualsSectionCount_oneEach() {
        let sections = (0..<4).map { MenuSection.fixture(title: "M\($0)", count: 3) }
        let result = MenuLayout.distribute(sections, columns: 4)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.allSatisfy { $0.count == 1 })
    }

    func testDistribute_columnsExceedsSectionCount_oneEach() {
        // k >= sections.count → one section per column
        let sections = (0..<3).map { MenuSection.fixture(title: "M\($0)", count: 2) }
        let result = MenuLayout.distribute(sections, columns: 10)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.count == 1 })
    }

    func testDistribute_singleColumn_returnsAllInOne() {
        let sections = (0..<5).map { MenuSection.fixture(title: "M\($0)", count: 3) }
        let result = MenuLayout.distribute(sections, columns: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].count, 5)
    }

    // MARK: Order preservation

    func testDistribute_preservesMenuBarOrder_withinColumns() {
        let titles = ["Apple", "File", "Edit", "View", "Format", "Window", "Help"]
        let sections = titles.map { MenuSection.fixture(title: $0, count: 4) }
        let result = MenuLayout.distribute(sections, columns: 3)
        let flatTitles = result.flatMap { $0.map(\.title) }
        XCTAssertEqual(flatTitles, titles,
                       "Sections must appear in original menu-bar order across all columns")
    }

    func testDistribute_preservesOrder_twoColumns() {
        let sections = (0..<6).map { MenuSection.fixture(title: "\($0)", count: 3) }
        let result = MenuLayout.distribute(sections, columns: 2)
        let flatOrder = result.flatMap { $0.map(\.title) }
        XCTAssertEqual(flatOrder, sections.map(\.title))
    }

    // MARK: No empty slices

    func testDistribute_noEmptyColumns_uniformSections() {
        let sections = (0..<8).map { MenuSection.fixture(title: "M\($0)", count: 4) }
        let result = MenuLayout.distribute(sections, columns: 3)
        XCTAssertTrue(result.allSatisfy { !$0.isEmpty },
                      "distribute must never produce an empty column")
    }

    func testDistribute_noEmptyColumns_unevenSections() {
        // Deliberately varied heights to exercise the binary search
        let configs: [(String, Int)] = [
            ("File", 10), ("Edit", 2), ("View", 8), ("Format", 1),
            ("Insert", 6), ("Tools", 3), ("Window", 4), ("Help", 1)
        ]
        let sections = configs.map { MenuSection.fixture(title: $0, count: $1) }
        for k in 2...4 {
            let result = MenuLayout.distribute(sections, columns: k)
            XCTAssertTrue(result.allSatisfy { !$0.isEmpty },
                          "columns=\(k) produced an empty slice")
        }
    }

    // MARK: Column count ≤ requested

    func testDistribute_resultCountNeverExceedsRequest() {
        let sections = (0..<8).map { MenuSection.fixture(title: "M\($0)", count: 3) }
        for k in 1...6 {
            let result = MenuLayout.distribute(sections, columns: k)
            XCTAssertLessThanOrEqual(result.count, k,
                                     "columns=\(k) returned \(result.count) slices")
        }
    }

    // MARK: Balance — binary-searched capacity actually minimises tallest column

    func testDistribute_balanced_equalWeightSections() {
        // 4 equal sections into 2 columns → must split 2+2, not 3+1
        let sections = (0..<4).map { MenuSection.fixture(title: "M\($0)", count: 5) }
        let result = MenuLayout.distribute(sections, columns: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].count, 2)
        XCTAssertEqual(result[1].count, 2)
    }

    func testDistribute_balanced_tallestColumnIsMinimal() {
        // 6 equal sections into 3 columns → 2 each; tallest = 2 sections worth
        let sections = (0..<6).map { MenuSection.fixture(title: "M\($0)", count: 4) }
        let result = MenuLayout.distribute(sections, columns: 3)
        XCTAssertEqual(result.count, 3)

        let heights = result.map { col in
            col.map { MenuLayout.height(of: $0) + MenuLayout.sectionSpacing }.reduce(0, +)
        }
        let maxHeight = heights.max() ?? 0

        // Verify no reordering could reduce the tallest column.
        // With 6 equal sections and 3 columns the only way to get a
        // shorter maximum is to put 1 section in some column, which
        // leaves 5 sections for 2 columns → at least 3 in one → taller.
        // So 2+2+2 is provably optimal.
        for col in result {
            let colHeight = col.map { MenuLayout.height(of: $0) + MenuLayout.sectionSpacing }.reduce(0, +)
            XCTAssertEqual(colHeight, maxHeight, accuracy: 0.001,
                           "Columns are not balanced: \(heights)")
        }
    }

    func testDistribute_singleHeavySection_isolatedInOwnColumn() {
        // One very tall section followed by many small ones.
        // The heavy section always ends up alone because the greedy packer
        // places it in its own column when the current column is non-empty.
        let heavy  = MenuSection.fixture(title: "Heavy", count: 30)
        let smalls = (0..<4).map { MenuSection.fixture(title: "S\($0)", count: 1) }
        let sections = [heavy] + smalls

        let result = MenuLayout.distribute(sections, columns: 3)

        // The heavy section must be the sole occupant of the first column.
        XCTAssertEqual(result[0].count, 1)
        XCTAssertEqual(result[0][0].title, "Heavy")
    }

    func testDistribute_usesMaxColumnsWhenTallSectionDominates() {
        // 5 sections with varying heights + one very tall section (Window).
        // Window dominates, so any valid k-column layout has Window alone in one
        // column and the max height is Window's height regardless of how the
        // short sections are split. The binary search (with lo = 0) must therefore
        // fill all k = 4 columns rather than collapsing short sections together.
        let window  = MenuSection.fixture(title: "Window", count: 30)  // ~714 pt
        let apple   = MenuSection.fixture(title: "Apple",   count: 5)  // ~139 pt
        let ghostty = MenuSection.fixture(title: "Ghostty", count: 8)  // ~208 pt
        let file    = MenuSection.fixture(title: "File",    count: 3)  // ~93 pt
        let view    = MenuSection.fixture(title: "View",    count: 6)  // ~162 pt
        // [Apple, Ghostty, File, View, Window] — 5 sections, k = 4.
        let sections = [apple, ghostty, file, view, window]
        let result = MenuLayout.distribute(sections, columns: 4)
        XCTAssertEqual(result.count, 4,
                       "Should fill all 4 allowed columns when tall section dominates")
        // Window must be alone in the last column.
        XCTAssertEqual(result.last!.count, 1)
        XCTAssertEqual(result.last![0].title, "Window")
    }
}

// MARK: - MenuLayout.consolidateTrailing tests

final class MenuLayoutConsolidateTrailingTests: XCTestCase {

    func testConsolidate_singleColumn_unchanged() {
        let col = [MenuSection.fixture(title: "File", count: 5)]
        let result = MenuLayout.consolidateTrailing([col])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].count, 1)
    }

    func testConsolidate_balancedColumns_unchanged() {
        // Two equally-tall columns: last is 100 % of the other, not < 30 % → no merge.
        let a = MenuSection.fixture(title: "File", count: 5)
        let b = MenuSection.fixture(title: "Edit", count: 5)
        let result = MenuLayout.consolidateTrailing([[a], [b]])
        XCTAssertEqual(result.count, 2)
    }

    func testConsolidate_tinyTrailingColumn_mergedIntoPrevious() {
        // last column has 1 item; tallest other has 30 items — ratio ≈ 3 % → merge.
        let tall = MenuSection.fixture(title: "Window", count: 30)
        let tiny = MenuSection.fixture(title: "Help", count: 1)
        let result = MenuLayout.consolidateTrailing([[tall], [tiny]])
        XCTAssertEqual(result.count, 1, "Tiny trailing column should be merged")
        XCTAssertEqual(result[0].map(\.title), ["Window", "Help"])
    }

    func testConsolidate_threeColumns_tinyLast_mergedIntoPrevious() {
        // Three columns; last is tiny relative to the Window column.
        let col1 = [MenuSection.fixture(title: "Apple", count: 5),
                    MenuSection.fixture(title: "File",  count: 8)]
        let col2 = [MenuSection.fixture(title: "Window", count: 30)]
        let col3 = [MenuSection.fixture(title: "Help", count: 1)]
        let result = MenuLayout.consolidateTrailing([col1, col2, col3])
        XCTAssertEqual(result.count, 2, "Three-column layout should consolidate to two")
        XCTAssertEqual(result[1].map(\.title), ["Window", "Help"])
    }

    func testConsolidate_threeBalancedColumns_unchanged() {
        // All three columns roughly equal — none qualifies as tiny.
        let cols = (0..<3).map { i in [MenuSection.fixture(title: "M\(i)", count: 5)] }
        let result = MenuLayout.consolidateTrailing(cols)
        XCTAssertEqual(result.count, 3)
    }

    func testConsolidate_preservesMenuBarOrder() {
        // After merge, sections must remain in original menu-bar order.
        let sections = ["Apple", "Ghostty", "File", "Edit", "View", "Window", "Help"]
        let col1 = sections.prefix(5).map { MenuSection.fixture(title: $0, count: 5) }
        let col2 = [MenuSection.fixture(title: "Window", count: 30)]
        let col3 = [MenuSection.fixture(title: "Help", count: 1)]
        let result = MenuLayout.consolidateTrailing([Array(col1), col2, col3])
        let allTitles = result.flatMap { $0.map(\.title) }
        XCTAssertEqual(allTitles, Array(sections.prefix(5)) + ["Window", "Help"],
                       "Menu-bar order must be preserved across the merge")
    }
}

// MARK: - MenuLayout.split tests

final class MenuLayoutSplitTests: XCTestCase {

    // MARK: Pass-through

    func testSplit_shortSection_notSplit() {
        let section = MenuSection.fixture(title: "File", count: 3)
        let maxH = MenuLayout.height(of: section) + 1
        let result = MenuLayout.split([section], maxHeight: maxH)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, section.id)
    }

    func testSplit_emptySections_returnsEmpty() {
        XCTAssertTrue(MenuLayout.split([], maxHeight: 500).isEmpty)
    }

    func testSplit_maxHeightTooSmall_returnsOriginal() {
        // maxHeight ≤ headerHeight — guard returns early, nothing is split
        let section = MenuSection.fixture(title: "Edit", count: 5)
        let result = MenuLayout.split([section], maxHeight: MenuLayout.headerHeight - 1)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: Splitting

    func testSplit_tallSection_producesMultiplePieces() {
        // 20 shortcuts — tall enough that a small maxHeight forces a split
        let section = MenuSection.fixture(title: "Bearbeiten", count: 20)
        let maxH = MenuLayout.height(of: MenuSection.fixture(title: "Bearbeiten", count: 8))
        let result = MenuLayout.split([section], maxHeight: maxH)
        XCTAssertGreaterThan(result.count, 1)
    }

    func testSplit_allPiecesShareTitle() {
        let section = MenuSection.fixture(title: "Edit", count: 30)
        let maxH = MenuLayout.height(of: MenuSection.fixture(title: "Edit", count: 10))
        let result = MenuLayout.split([section], maxHeight: maxH)
        XCTAssertTrue(result.allSatisfy { $0.title == "Edit" })
    }

    func testSplit_allShortcutsPreserved() {
        let section = MenuSection.fixture(title: "Edit", count: 25)
        let maxH = MenuLayout.height(of: MenuSection.fixture(title: "Edit", count: 8))
        let result = MenuLayout.split([section], maxHeight: maxH)
        let allShortcuts = result.flatMap { $0.shortcuts }
        XCTAssertEqual(allShortcuts.count, 25)
    }

    func testSplit_eachPieceFitsWithinMaxHeight() {
        let section = MenuSection.fixture(title: "Edit", count: 30)
        let maxH = MenuLayout.height(of: MenuSection.fixture(title: "Edit", count: 10))
        let result = MenuLayout.split([section], maxHeight: maxH)
        for piece in result {
            XCTAssertLessThanOrEqual(MenuLayout.height(of: piece), maxH + 0.001,
                                     "Piece '\(piece.title)' height \(MenuLayout.height(of: piece)) exceeds maxH \(maxH)")
        }
    }

    func testSplit_multipleGroups_splitsAtGroupBoundaries() {
        // Two named groups, each just under half of maxH; together they exceed maxH
        let groupH = MenuLayout.height(of: MenuSection.fixture(title: "T", groups: [("G", 5)]))
        let maxH = groupH * 1.5   // two groups together exceed this
        let section = MenuSection.fixture(title: "Edit", groups: [("G1", 5), ("G2", 5)])
        let result = MenuLayout.split([section], maxHeight: maxH)
        // Each group ends up in its own piece
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].groups.count, 1)
        XCTAssertEqual(result[1].groups.count, 1)
    }

    func testSplit_preservesOrderAcrossPieces() {
        let section = MenuSection.fixture(title: "Edit", count: 20)
        let maxH = MenuLayout.height(of: MenuSection.fixture(title: "Edit", count: 7))
        let result = MenuLayout.split([section], maxHeight: maxH)
        let originalTitles = section.shortcuts.map(\.title)
        let splitTitles = result.flatMap { $0.shortcuts.map(\.title) }
        XCTAssertEqual(splitTitles, originalTitles)
    }

    func testSplit_shortSectionsMixed_onlyTallOnesSplit() {
        let short = MenuSection.fixture(title: "Help", count: 2)
        let tall  = MenuSection.fixture(title: "Edit", count: 30)
        let maxH  = MenuLayout.height(of: MenuSection.fixture(title: "Edit", count: 10))
        let result = MenuLayout.split([short, tall], maxHeight: maxH)
        // "Help" (2 items) is short → not split; "Edit" (30 items) → split
        let helpPieces = result.filter { $0.title == "Help" }
        let editPieces = result.filter { $0.title == "Edit" }
        XCTAssertEqual(helpPieces.count, 1)
        XCTAssertGreaterThan(editPieces.count, 1)
    }
}
