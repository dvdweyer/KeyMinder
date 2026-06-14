// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

final class ShortcutFormatterTests: XCTestCase {

    // MARK: - Modifier string ordering & bit decoding

    func testModifiers_commandOnly() {
        // modifiers = 0: no shift/option/control bits set, bit-8 clear → command implied
        XCTAssertEqual(format(cmdChar: "n", modifiers: 0), "⌘N")
    }

    func testModifiers_shift() {
        // bit 1 (shift) + command implied
        XCTAssertEqual(format(cmdChar: "n", modifiers: 1), "⇧⌘N")
    }

    func testModifiers_option() {
        // bit 2 (option) + command implied
        XCTAssertEqual(format(cmdChar: "n", modifiers: 2), "⌥⌘N")
    }

    func testModifiers_control() {
        // bit 4 (control) + command implied
        XCTAssertEqual(format(cmdChar: "n", modifiers: 4), "⌃⌘N")
    }

    func testModifiers_allFour() {
        // control(4)+option(2)+shift(1)=7, command implied → ⌃⌥⇧⌘ order
        XCTAssertEqual(format(cmdChar: "n", modifiers: 7), "⌃⌥⇧⌘N")
    }

    func testModifiers_noCommand() {
        // bit 8 set → no ⌘; no other bits → bare key
        XCTAssertEqual(format(cmdChar: "n", modifiers: 8), "N")
    }

    func testModifiers_controlNoCommand() {
        // control(4) + no-command(8) = 12
        XCTAssertEqual(format(cmdChar: "n", modifiers: 12), "⌃N")
    }

    func testModifiers_shiftNoCommand() {
        // shift(1) + no-command(8) = 9
        XCTAssertEqual(format(cmdChar: "n", modifiers: 9), "⇧N")
    }

    // MARK: - cmdChar: printable ASCII

    func testCmdChar_lowercase_isUppercased() {
        XCTAssertEqual(format(cmdChar: "s", modifiers: 0), "⌘S")
    }

    func testCmdChar_alreadyUppercase() {
        XCTAssertEqual(format(cmdChar: "S", modifiers: 0), "⌘S")
    }

    func testCmdChar_digit() {
        XCTAssertEqual(format(cmdChar: "1", modifiers: 0), "⌘1")
    }

    func testCmdChar_punctuation() {
        // 0x2C (,) is in the 0x21…0x7E printable range
        XCTAssertEqual(format(cmdChar: ",", modifiers: 0), "⌘,")
    }

    // MARK: - cmdChar: control characters

    func testCmdChar_tab() {
        // U+0009 → ⇥
        XCTAssertEqual(format(cmdChar: "\t", modifiers: 0), "⌘⇥")
    }

    func testCmdChar_return() {
        // U+000D → ↩
        XCTAssertEqual(format(cmdChar: "\r", modifiers: 0), "⌘↩")
    }

    func testCmdChar_escape() {
        // U+001B → ⎋
        XCTAssertEqual(format(cmdChar: "\u{1B}", modifiers: 0), "⌘⎋")
    }

    func testCmdChar_space() {
        // U+0020 → "Space" (string, not symbol)
        XCTAssertEqual(format(cmdChar: " ", modifiers: 0), "⌘Space")
    }

    func testCmdChar_backspace() {
        // U+0008 → ⌫
        XCTAssertEqual(format(cmdChar: "\u{08}", modifiers: 0), "⌘⌫")
    }

    func testCmdChar_delete() {
        // U+007F → ⌫  (same symbol as backspace)
        XCTAssertEqual(format(cmdChar: "\u{7F}", modifiers: 0), "⌘⌫")
    }

    // MARK: - cmdChar: NSEvent function-key range (0xF700+)

    func testCmdChar_upArrow() {
        XCTAssertEqual(format(cmdChar: fk(0xF700), modifiers: 0), "⌘↑")
    }

    func testCmdChar_downArrow() {
        XCTAssertEqual(format(cmdChar: fk(0xF701), modifiers: 0), "⌘↓")
    }

    func testCmdChar_leftArrow() {
        XCTAssertEqual(format(cmdChar: fk(0xF702), modifiers: 0), "⌘←")
    }

    func testCmdChar_rightArrow() {
        XCTAssertEqual(format(cmdChar: fk(0xF703), modifiers: 0), "⌘→")
    }

    func testCmdChar_F1() {
        XCTAssertEqual(format(cmdChar: fk(0xF704), modifiers: 0), "⌘F1")
    }

    func testCmdChar_F12() {
        XCTAssertEqual(format(cmdChar: fk(0xF70F), modifiers: 0), "⌘F12")
    }

    func testCmdChar_forwardDelete() {
        XCTAssertEqual(format(cmdChar: fk(0xF728), modifiers: 0), "⌘⌦")
    }

    func testCmdChar_pageUp() {
        XCTAssertEqual(format(cmdChar: fk(0xF72C), modifiers: 0), "⌘⇞")
    }

    func testCmdChar_pageDown() {
        XCTAssertEqual(format(cmdChar: fk(0xF72D), modifiers: 0), "⌘⇟")
    }

    func testCmdChar_unknownFunctionKey_returnsNil() {
        // 0xF7FF is in the 0xF700… range but not in the map
        XCTAssertNil(format(cmdChar: fk(0xF7FF), modifiers: 0))
    }

    // MARK: - Glyph fallback

    func testGlyph_tab() {
        // cmdChar nil; glyph 0x02 → ⇥
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: 0x02, modifiers: 0), "⌘⇥")
    }

    func testGlyph_escape() {
        // glyph 0x1B → ⎋
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: 0x1B, modifiers: 0), "⌘⎋")
    }

    func testGlyph_backspace() {
        // glyph 0x17 → ⌫
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: 0x17, modifiers: 0), "⌘⌫")
    }

    func testGlyph_return() {
        // glyph 0x0B → ↩
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: 0x0B, modifiers: 0), "⌘↩")
    }

    func testGlyph_zero_isIgnored() {
        // glyph 0 is explicitly skipped; no virtualKey either → nil
        XCTAssertNil(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: 0, modifiers: 0))
    }

    func testGlyph_unknownValue_returnsNil() {
        // glyph 0xFF is not in the map and cmdChar/virtualKey are nil → nil
        XCTAssertNil(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: 0xFF, modifiers: 0))
    }

    // MARK: - Virtual-key fallback

    func testVirtualKey_return() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x24, glyph: nil, modifiers: 0), "⌘↩")
    }

    func testVirtualKey_tab() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x30, glyph: nil, modifiers: 0), "⌘⇥")
    }

    func testVirtualKey_space() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x31, glyph: nil, modifiers: 0), "⌘Space")
    }

    func testVirtualKey_escape() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x35, glyph: nil, modifiers: 0), "⌘⎋")
    }

    func testVirtualKey_leftArrow() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x7B, glyph: nil, modifiers: 0), "⌘←")
    }

    func testVirtualKey_rightArrow() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x7C, glyph: nil, modifiers: 0), "⌘→")
    }

    func testVirtualKey_upArrow() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x7E, glyph: nil, modifiers: 0), "⌘↑")
    }

    func testVirtualKey_downArrow() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x7D, glyph: nil, modifiers: 0), "⌘↓")
    }

    func testVirtualKey_F5() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x60, glyph: nil, modifiers: 0), "⌘F5")
    }

    func testVirtualKey_F1() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x7A, glyph: nil, modifiers: 0), "⌘F1")
    }

    func testVirtualKey_F12() {
        XCTAssertEqual(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x6F, glyph: nil, modifiers: 0), "⌘F12")
    }

    func testVirtualKey_unknown_returnsNil() {
        XCTAssertNil(ShortcutFormatter.format(cmdChar: nil, virtualKey: 0xFFFF, glyph: nil, modifiers: 0))
    }

    // MARK: - Priority: cmdChar > glyph > virtualKey

    func testPriority_cmdCharOverGlyph() {
        // cmdChar "s" should win over glyph 0x1B (escape)
        XCTAssertEqual(
            ShortcutFormatter.format(cmdChar: "s", virtualKey: nil, glyph: 0x1B, modifiers: 0),
            "⌘S"
        )
    }

    func testPriority_cmdCharOverVirtualKey() {
        // cmdChar "s" wins over virtualKey 0x35 (escape)
        XCTAssertEqual(
            ShortcutFormatter.format(cmdChar: "s", virtualKey: 0x35, glyph: nil, modifiers: 0),
            "⌘S"
        )
    }

    func testPriority_glyphOverVirtualKey() {
        // glyph 0x02 (⇥ tab) wins over virtualKey 0x7E (↑ up arrow)
        XCTAssertEqual(
            ShortcutFormatter.format(cmdChar: nil, virtualKey: 0x7E, glyph: 0x02, modifiers: 0),
            "⌘⇥"
        )
    }

    // MARK: - Returns nil when nothing is set

    func testAllNil_returnsNil() {
        XCTAssertNil(ShortcutFormatter.format(cmdChar: nil, virtualKey: nil, glyph: nil, modifiers: 0))
    }

    func testEmptyCmdChar_treatedAsUnknown() {
        // An empty string has no first scalar → falls through to glyph/virtualKey (both nil) → nil
        XCTAssertNil(ShortcutFormatter.format(cmdChar: "", virtualKey: nil, glyph: nil, modifiers: 0))
    }

    // MARK: - keys(keyCode:modifierFlags:) — NSEvent-based matching

    func testKeysFromEvent_commandLetter() {
        // keyCode 1 = 's' on standard keyboard; charactersIgnoringModifiers = "s"
        XCTAssertEqual(keys(keyCode: 1, flags: .command, chars: "s"), "⌘S")
    }

    func testKeysFromEvent_shiftCommand() {
        XCTAssertEqual(keys(keyCode: 45, flags: [.shift, .command], chars: "n"), "⇧⌘N")
    }

    func testKeysFromEvent_controlLetter() {
        XCTAssertEqual(keys(keyCode: 8, flags: .control, chars: "c"), "⌃C")
    }

    func testKeysFromEvent_optionCommandLetter() {
        XCTAssertEqual(keys(keyCode: 3, flags: [.option, .command], chars: "f"), "⌥⌘F")
    }

    func testKeysFromEvent_controlOptionShiftCommand() {
        XCTAssertEqual(keys(keyCode: 40, flags: [.control, .option, .shift, .command], chars: "k"), "⌃⌥⇧⌘K")
    }

    func testKeysFromEvent_upArrow() {
        // keyCode 0x7E = up arrow; in virtualKeyMap → takes priority over chars
        XCTAssertEqual(keys(keyCode: 0x7E, flags: .command, chars: nil), "⌘↑")
    }

    func testKeysFromEvent_downArrow() {
        XCTAssertEqual(keys(keyCode: 0x7D, flags: .command, chars: nil), "⌘↓")
    }

    func testKeysFromEvent_leftArrow() {
        XCTAssertEqual(keys(keyCode: 0x7B, flags: .command, chars: nil), "⌘←")
    }

    func testKeysFromEvent_rightArrow() {
        XCTAssertEqual(keys(keyCode: 0x7C, flags: .command, chars: nil), "⌘→")
    }

    func testKeysFromEvent_F5() {
        XCTAssertEqual(keys(keyCode: 0x60, flags: .command, chars: nil), "⌘F5")
    }

    func testKeysFromEvent_space() {
        XCTAssertEqual(keys(keyCode: 0x31, flags: .command, chars: nil), "⌘Space")
    }

    func testKeysFromEvent_delete() {
        XCTAssertEqual(keys(keyCode: 0x33, flags: .command, chars: nil), "⌘⌫")
    }

    func testKeysFromEvent_noModifiers_returnsNonEmptyString() {
        // Bare letter with no modifiers — should still produce a string (e.g. "S")
        XCTAssertEqual(keys(keyCode: 1, flags: [], chars: "s"), "S")
    }

    func testKeysFromEvent_unknownKeyCode_noChars_returnsNil() {
        XCTAssertNil(keys(keyCode: 0xFF, flags: .command, chars: nil))
    }

    func testKeysFromEvent_digit() {
        XCTAssertEqual(keys(keyCode: 18, flags: .command, chars: "1"), "⌘1")
    }

    // MARK: - Helpers

    /// Shorthand for calling format with only cmdChar + modifiers.
    private func format(cmdChar: String, modifiers: Int) -> String? {
        ShortcutFormatter.format(cmdChar: cmdChar, virtualKey: nil, glyph: nil, modifiers: modifiers)
    }

    /// Shorthand for `keys(keyCode:modifierFlags:charactersIgnoringModifiers:)`.
    private func keys(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String?) -> String? {
        ShortcutFormatter.keys(keyCode: keyCode, modifierFlags: flags,
                               charactersIgnoringModifiers: chars)
    }

    /// Returns the single-character String for a Unicode scalar in the NSEvent
    /// function-key private-use range (0xF700+).
    private func fk(_ value: UInt32) -> String {
        String(UnicodeScalar(value)!)
    }
}
