// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class ScrapedStringPolicyTests: XCTestCase {

    // MARK: - Normal strings pass through unchanged

    func testNormalTitle_preserved() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Save As…"), "Save As…")
    }

    func testEmptyString_returnsEmpty() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize(""), "")
    }

    func testPunctuation_preserved() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Copy & Paste (All)"), "Copy & Paste (All)")
    }

    func testUnicodeLetters_preserved() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("日本語メニュー"), "日本語メニュー")
    }

    // MARK: - NFC normalization

    func testNFC_combiningAccent_merges() {
        // U+0065 + U+0301 (e + combining acute) → U+00E9 (é precomposed)
        let nfd = "e\u{0301}"  // two scalars
        let nfc = "\u{00E9}"   // one scalar
        XCTAssertEqual(ScrapedStringPolicy.sanitize(nfd), nfc)
    }

    func testNFC_alreadyPrecomposed_unchanged() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("café"), "café")
    }

    // MARK: - C0 control characters stripped

    func testC0_null_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("ab\u{0000}cd"), "abcd")
    }

    func testC0_SOH_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("\u{0001}Save"), "Save")
    }

    func testC0_US_stripped() {
        // U+001F (Unit Separator) — last C0 control
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Save\u{001F}File"), "SaveFile")
    }

    func testC0_space_preserved() {
        // U+0020 is just above the C0 range and must be kept
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Save File"), "Save File")
    }

    // MARK: - C1 control characters stripped

    func testC1_PAD_stripped() {
        // U+0080 (PAD) — first C1 control
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Hi\u{0080}There"), "HiThere")
    }

    func testC1_APC_stripped() {
        // U+009F (APC) — last C1 control
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Hi\u{009F}There"), "HiThere")
    }

    func testC1_boundary_above_preserved() {
        // U+00A0 (NO-BREAK SPACE) is above the C1 range — keep it
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{00A0}B"), "A\u{00A0}B")
    }

    // MARK: - Bidi control characters stripped

    func testBidi_RLO_stripped() {
        // U+202E (RIGHT-TO-LEFT OVERRIDE) — the classic text-spoofing scalar
        XCTAssertEqual(ScrapedStringPolicy.sanitize("Hello\u{202E}World"), "HelloWorld")
    }

    func testBidi_LRO_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("\u{202D}Title"), "Title")
    }

    func testBidi_RLE_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{202B}B"), "AB")
    }

    func testBidi_LRE_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{202A}B"), "AB")
    }

    func testBidi_PDF_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{202C}B"), "AB")
    }

    func testBidi_LRM_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{200E}B"), "AB")
    }

    func testBidi_RLM_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{200F}B"), "AB")
    }

    func testBidi_ALM_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{061C}B"), "AB")
    }

    func testBidi_LRI_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{2066}B"), "AB")
    }

    func testBidi_RLI_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{2067}B"), "AB")
    }

    func testBidi_FSI_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{2068}B"), "AB")
    }

    func testBidi_PDI_stripped() {
        XCTAssertEqual(ScrapedStringPolicy.sanitize("A\u{2069}B"), "AB")
    }

    // MARK: - Combined attack vectors

    func testAttack_rloSpoofedSave() {
        // Title visually reads "evaSave" or similar after the RLO flip — sanitized to "Save"
        let attack = "\u{202E}evaS"  // RLO + "evaS" renders RTL as "Save"
        XCTAssertEqual(ScrapedStringPolicy.sanitize(attack), "evaS")
    }

    func testAttack_mixedControlsAndBidi() {
        let attack = "\u{0001}\u{202E}Open\u{0000}File\u{202C}"
        XCTAssertEqual(ScrapedStringPolicy.sanitize(attack), "OpenFile")
    }

    // MARK: - Length cap

    func testLengthCap_longStringTruncated() {
        let long = String(repeating: "A", count: 300)
        let result = ScrapedStringPolicy.sanitize(long)
        XCTAssertEqual(result.count, ScrapedStringPolicy.maxLength)
    }

    func testLengthCap_atLimitPassesThrough() {
        let exactly = String(repeating: "B", count: ScrapedStringPolicy.maxLength)
        XCTAssertEqual(ScrapedStringPolicy.sanitize(exactly), exactly)
    }

    func testLengthCap_belowLimitPreserved() {
        let short = "Hello"
        XCTAssertEqual(ScrapedStringPolicy.sanitize(short), short)
    }
}
