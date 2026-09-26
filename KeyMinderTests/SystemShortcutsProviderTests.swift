// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class SystemShortcutsProviderTests: XCTestCase {

    private func title(_ raw: String) -> String {
        SystemShortcutsProvider.displayTitle(forUserKeyEquivalentKey: raw)
    }

    func testPlainTitle_unchanged() {
        XCTAssertEqual(title("Save As…"), "Save As…")
    }

    func testMenuPath_twoLevels() {
        XCTAssertEqual(title("\u{1b}File\u{1b}Save"), "File › Save")
    }

    func testMenuPath_threeLevels() {
        XCTAssertEqual(title("\u{1b}Format\u{1b}Font\u{1b}Bold"), "Format › Font › Bold")
    }

    func testMenuPath_emptyComponentsDropped() {
        XCTAssertEqual(title("\u{1b}File\u{1b}\u{1b}Save\u{1b}"), "File › Save")
    }

    func testMenuPath_onlySeparators_isEmpty() {
        XCTAssertEqual(title("\u{1b}\u{1b}"), "")
    }

    func testMenuPath_componentsSanitized() {
        XCTAssertEqual(title("\u{1b}Fi\u{202E}le\u{1b}Sa\u{07}ve"), "File › Save")
    }
}
