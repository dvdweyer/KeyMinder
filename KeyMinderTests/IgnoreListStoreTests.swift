// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

/// Tests `IgnoreListStore.isIgnored(title:patterns:)` — the pure, nonisolated matcher.
final class IgnoreListStoreTests: XCTestCase {

    // MARK: Exact-match fast path

    func testExactMatch() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "Minimize", patterns: ["Minimize"]))
    }

    func testExactMatchIsCaseInsensitive() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "minimize", patterns: ["MINIMIZE"]))
    }

    func testExactMatchIsDiacriticInsensitive() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "Centre", patterns: ["Céntre"]))
    }

    func testExactMatchNoMatch() {
        XCTAssertFalse(IgnoreListStore.isIgnored(title: "Zoom", patterns: ["Minimize"]))
    }

    func testExactMatchDoesNotSubstringMatch() {
        // "Zoom All" should not match a pattern of just "Zoom" under exact-match semantics.
        XCTAssertFalse(IgnoreListStore.isIgnored(title: "Zoom All", patterns: ["Zoom"]))
    }

    // MARK: Wildcard fallback

    func testWildcardStarMatch() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "Zoom All Windows", patterns: ["Zoom*"]))
    }

    func testWildcardQuestionMarkMatch() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "Tab 1", patterns: ["Tab ?"]))
    }

    func testWildcardIsCaseInsensitive() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "MINIMIZE ALL", patterns: ["minimize*"]))
    }

    func testWildcardNoMatch() {
        XCTAssertFalse(IgnoreListStore.isIgnored(title: "Fullscreen", patterns: ["Zoom*"]))
    }

    // MARK: Multiple patterns / empty input

    func testMatchesAnyPatternInList() {
        XCTAssertTrue(IgnoreListStore.isIgnored(title: "Fill", patterns: ["Minimize", "Fill", "Move*"]))
    }

    func testNoPatternsNeverMatches() {
        XCTAssertFalse(IgnoreListStore.isIgnored(title: "Anything", patterns: []))
    }

    func testEmptyTitleNoMatch() {
        XCTAssertFalse(IgnoreListStore.isIgnored(title: "", patterns: ["Minimize"]))
    }
}
