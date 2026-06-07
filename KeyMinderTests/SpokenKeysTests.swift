import XCTest
@testable import KeyMinder

final class SpokenKeysTests: XCTestCase {

    // MARK: - Empty input

    func testEmpty() {
        XCTAssertEqual(spokenKeys(""), "")
    }

    // MARK: - Modifier glyphs

    func testCommand() {
        XCTAssertEqual(spokenKeys("⌘"), "Command")
    }

    func testShift() {
        XCTAssertEqual(spokenKeys("⇧"), "Shift")
    }

    func testOption() {
        XCTAssertEqual(spokenKeys("⌥"), "Option")
    }

    func testControl() {
        XCTAssertEqual(spokenKeys("⌃"), "Control")
    }

    // MARK: - Modifier + key combinations

    func testShiftCommandN() {
        XCTAssertEqual(spokenKeys("⇧⌘N"), "Shift Command N")
    }

    func testAllFourModifiers() {
        XCTAssertEqual(spokenKeys("⌃⌥⇧⌘X"), "Control Option Shift Command X")
    }

    // MARK: - Special keys

    func testReturn() {
        XCTAssertEqual(spokenKeys("↩"), "Return")
    }

    func testEscape() {
        XCTAssertEqual(spokenKeys("⎋"), "Escape")
    }

    func testDelete() {
        XCTAssertEqual(spokenKeys("⌫"), "Delete")
    }

    func testTab() {
        XCTAssertEqual(spokenKeys("⇥"), "Tab")
    }

    func testUpArrow() {
        XCTAssertEqual(spokenKeys("↑"), "Up Arrow")
    }

    func testDownArrow() {
        XCTAssertEqual(spokenKeys("↓"), "Down Arrow")
    }

    func testLeftArrow() {
        XCTAssertEqual(spokenKeys("←"), "Left Arrow")
    }

    func testRightArrow() {
        XCTAssertEqual(spokenKeys("→"), "Right Arrow")
    }

    // MARK: - Space token (multi-character word, not a space character)

    func testSpaceAlone() {
        XCTAssertEqual(spokenKeys("Space"), "Space")
    }

    func testCommandSpace() {
        XCTAssertEqual(spokenKeys("⌘Space"), "Command Space")
    }

    func testControlSpace() {
        XCTAssertEqual(spokenKeys("⌃Space"), "Control Space")
    }

    // MARK: - Fn keys

    func testF1() {
        XCTAssertEqual(spokenKeys("F1"), "F1")
    }

    func testF5() {
        XCTAssertEqual(spokenKeys("F5"), "F5")
    }

    func testCommandF5() {
        XCTAssertEqual(spokenKeys("⌘F5"), "Command F5")
    }

    func testF12() {
        XCTAssertEqual(spokenKeys("F12"), "F12")
    }

    func testCommandF12() {
        XCTAssertEqual(spokenKeys("⌘F12"), "Command F12")
    }

    // MARK: - Regular letters and digits

    func testLetter_uppercased() {
        XCTAssertEqual(spokenKeys("n"), "N")
    }

    func testCommandLetter() {
        XCTAssertEqual(spokenKeys("⌘S"), "Command S")
    }

    func testDigit() {
        XCTAssertEqual(spokenKeys("⌘1"), "Command 1")
    }
}
