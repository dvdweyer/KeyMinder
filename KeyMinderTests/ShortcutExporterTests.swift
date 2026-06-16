// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class ShortcutExporterTests: XCTestCase {

    // MARK: - Helpers

    private func app(name: String, sections: [MenuSection]) -> AppShortcuts {
        AppShortcuts(appName: name, bundleIdentifier: nil, icon: nil,
                     sections: sections, includesItemsWithoutShortcuts: false)
    }

    private func section(_ title: String, groups: [ShortcutGroup]) -> MenuSection {
        MenuSection(title: title, groups: groups)
    }

    private func group(_ title: String? = nil, shortcuts: [Shortcut]) -> ShortcutGroup {
        ShortcutGroup(title: title, shortcuts: shortcuts)
    }

    private func shortcut(_ title: String, keys: String) -> Shortcut {
        Shortcut(title: title, keys: keys)
    }

    // MARK: - Normal output

    func testBasic_outputStructure() {
        let result = ShortcutExporter.markdown(for: app(name: "Finder", sections: [
            section("File", groups: [group(shortcuts: [shortcut("New Window", keys: "⌘N")])])
        ]))
        XCTAssertTrue(result.contains("# Finder"))
        XCTAssertTrue(result.contains("## File"))
        XCTAssertTrue(result.contains("`⌘N` — New Window"))
    }

    func testSubmenu_includesH3Header() {
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("Edit", groups: [group("Transformations", shortcuts: [shortcut("Make Uppercase", keys: "⌃⌘U")])])
        ]))
        XCTAssertTrue(result.contains("### Transformations"))
        XCTAssertTrue(result.contains("`⌃⌘U` — Make Uppercase"))
    }

    func testEmpty_sections_omitted() {
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("File", groups: [group(shortcuts: [shortcut("Open", keys: "")])])
        ]))
        XCTAssertFalse(result.contains("## File"), "Section with only unkeyed shortcuts should be omitted")
    }

    // MARK: - Markdown injection prevention

    func testAppName_backtick_escaped() {
        let result = ShortcutExporter.markdown(for: app(name: "My`App", sections: [
            section("File", groups: [group(shortcuts: [shortcut("New", keys: "⌘N")])])
        ]))
        XCTAssertTrue(result.contains("# My\\`App"))
    }

    func testAppName_imageInjection_escaped() {
        // A hostile app name containing ![](url) — the [ must be escaped
        let result = ShortcutExporter.markdown(for: app(name: "App![](http://evil/x)", sections: [
            section("File", groups: [group(shortcuts: [shortcut("New", keys: "⌘N")])])
        ]))
        XCTAssertFalse(result.contains("![]("), "Image injection must be escaped")
        XCTAssertTrue(result.contains("\\!\\[\\]"))
    }

    func testSectionTitle_linkInjection_escaped() {
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("[Fake Link](http://evil)", groups: [group(shortcuts: [shortcut("Open", keys: "⌘O")])])
        ]))
        XCTAssertFalse(result.contains("[Fake Link]("), "Link in section title must be escaped")
    }

    func testShortcutTitle_backtick_escaped() {
        // A title with a backtick could otherwise break the code span around the keys.
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("Edit", groups: [group(shortcuts: [shortcut("Paste`Special", keys: "⌘V")])])
        ]))
        XCTAssertTrue(result.contains("Paste\\`Special"))
    }

    func testShortcutTitle_htmlAngle_escaped() {
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("Edit", groups: [group(shortcuts: [shortcut("Copy <All>", keys: "⌘C")])])
        ]))
        XCTAssertTrue(result.contains("Copy \\<All\\>"))
    }

    func testGroupTitle_plainText_passesThrough() {
        // Plain-text titles need no escaping and should appear as-is.
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("System", groups: [group("Move & Resize", shortcuts: [shortcut("Cmd", keys: "⌘Z")])])
        ]))
        XCTAssertTrue(result.contains("### Move & Resize"))
    }

    func testKeys_backtick_usesFencedCodeSpan() {
        // A key string containing a backtick must use double-backtick delimiters
        // (CommonMark §6.1) so the backtick is safe inside the code span.
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("Edit", groups: [group(shortcuts: [shortcut("Run", keys: "⌘`")])])
        ]))
        XCTAssertTrue(result.contains("`` ⌘` ``"))
    }

    func testNormalTitle_notOverEscaped() {
        // Common characters like hyphen, period, parenthesis should NOT be escaped.
        let result = ShortcutExporter.markdown(for: app(name: "App", sections: [
            section("File", groups: [group(shortcuts: [shortcut("Save As… (All)", keys: "⇧⌘S")])])
        ]))
        XCTAssertTrue(result.contains("Save As… (All)"),
                      "Common punctuation should not be over-escaped")
    }
}
