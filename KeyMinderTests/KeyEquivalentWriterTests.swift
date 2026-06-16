// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import AppKit
@testable import KeyMinder

final class KeyEquivalentWriterTests: XCTestCase {

    // MARK: - encode()

    func testEncode_command_letter_lowercased() {
        XCTAssertEqual(KeyEquivalentWriter.encode(modifiers: [.command], base: "N"), "@n")
        XCTAssertEqual(KeyEquivalentWriter.encode(modifiers: [.command], base: "n"), "@n")
    }

    func testEncode_shiftCommand_letter_usesDollarPrefix() {
        XCTAssertEqual(KeyEquivalentWriter.encode(modifiers: [.command, .shift], base: "a"), "@$a")
    }

    func testEncode_allModifiers_canonicalOrder() {
        // Canonical macOS order: Control, Option, Command, Shift.
        let v = KeyEquivalentWriter.encode(modifiers: [.command, .option, .control, .shift], base: "z")
        XCTAssertEqual(v, "^~@$z")
    }

    func testEncode_shiftWithDigit_keepsUnshiftedBase() {
        // The caller resolves the unshifted base ("1", not "!"); Shift stays the "$" prefix.
        XCTAssertEqual(KeyEquivalentWriter.encode(modifiers: [.command, .shift], base: "1"), "@$1")
    }

    func testEncode_punctuation_unshiftedBase() {
        XCTAssertEqual(KeyEquivalentWriter.encode(modifiers: [.command, .shift], base: "/"), "@$/")
    }

    func testEncode_rejectsShiftOnlyAndBareKey() {
        XCTAssertNil(KeyEquivalentWriter.encode(modifiers: [], base: "a"))
        XCTAssertNil(KeyEquivalentWriter.encode(modifiers: [.shift], base: "a"))
    }

    // MARK: - Round-trip against the decoder

    /// Every encoded value must decode back to the expected display string via the
    /// in-repo reader, guaranteeing the writer and `SystemShortcutsProvider` agree.
    func testRoundTrip_decodesToExpectedDisplay() {
        let cases: [(NSEvent.ModifierFlags, Character, String)] = [
            ([.command],                   "n", "⌘N"),
            ([.command, .shift],           "a", "⇧⌘A"),
            ([.command, .shift],           "1", "⇧⌘1"),
            ([.command, .shift],           "/", "⇧⌘/"),
            ([.command, .option],          "k", "⌥⌘K"),
            ([.control, .command],         "d", "⌃⌘D"),
            ([.command, .option, .control, .shift], "z", "⌃⌥⇧⌘Z"),
        ]
        for (mods, base, expected) in cases {
            guard let value = KeyEquivalentWriter.encode(modifiers: mods, base: base) else {
                return XCTFail("encode returned nil for \(expected)")
            }
            XCTAssertEqual(SystemShortcutsProvider.formatUserKeyEquivalent(value), expected,
                           "round-trip mismatch for \(expected) (value: \(value))")
        }
    }

    // MARK: - Read / write against a throwaway domain

    private let testDomain = "org.afaik.KeyMinder.tests.\(UUID().uuidString)"

    override func tearDown() {
        // Clear the whole NSUserKeyEquivalents key from the scratch domain.
        CFPreferencesSetAppValue("NSUserKeyEquivalents" as CFString, nil, testDomain as CFString)
        CFPreferencesAppSynchronize(testDomain as CFString)
        super.tearDown()
    }

    func testAssign_thenReadBack() {
        XCTAssertFalse(KeyEquivalentWriter.hasEntry(title: "New Note", bundleID: testDomain))
        KeyEquivalentWriter.assign(title: "New Note", value: "@$n", bundleID: testDomain)
        XCTAssertTrue(KeyEquivalentWriter.hasEntry(title: "New Note", bundleID: testDomain))
        XCTAssertEqual(KeyEquivalentWriter.current(bundleID: testDomain)["New Note"], "@$n")
    }

    func testRemove_deletesEntry_andClearsEmptyDict() {
        KeyEquivalentWriter.assign(title: "Only", value: "@o", bundleID: testDomain)
        KeyEquivalentWriter.remove(title: "Only", bundleID: testDomain)
        XCTAssertFalse(KeyEquivalentWriter.hasEntry(title: "Only", bundleID: testDomain))
        // Removing the last entry should leave the key absent, not an empty dict.
        XCTAssertNil(CFPreferencesCopyAppValue("NSUserKeyEquivalents" as CFString, testDomain as CFString))
    }

    func testAssign_preservesOtherEntries() {
        KeyEquivalentWriter.assign(title: "First", value: "@1", bundleID: testDomain)
        KeyEquivalentWriter.assign(title: "Second", value: "@2", bundleID: testDomain)
        let dict = KeyEquivalentWriter.current(bundleID: testDomain)
        XCTAssertEqual(dict["First"], "@1")
        XCTAssertEqual(dict["Second"], "@2")
    }

    // MARK: - writeKey fallback

    func testWriteKey_prefersRawTitle() {
        let withRaw = Shortcut(title: "Save…", rawTitle: "Save\u{2026}", keys: "⌘S",
                               axElement: nil, isDisabled: false)
        XCTAssertEqual(withRaw.writeKey, "Save\u{2026}")

        let synthetic = Shortcut(title: "Save", keys: "⌘S")
        XCTAssertEqual(synthetic.writeKey, "Save")
    }
}
