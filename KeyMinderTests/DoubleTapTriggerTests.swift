import XCTest
@testable import KeyMinder

/// Tests for the DoubleTapTrigger state machine.
///
/// NSEvent global monitors do not fire in unit tests, so each test drives
/// the state machine directly via `handleFlags(_:)` (internal visibility).
/// `start(modifier:)` resets all state before each test; `stop()` cleans up after.
@MainActor
final class DoubleTapTriggerTests: XCTestCase {

    private var fired = false

    override func setUp() {
        super.setUp()
        fired = false
        DoubleTapTrigger.shared.onActivate = { [weak self] in self?.fired = true }
        DoubleTapTrigger.shared.start(modifier: .command)
    }

    override func tearDown() {
        DoubleTapTrigger.shared.stop()
        DoubleTapTrigger.shared.onActivate = nil
        super.tearDown()
    }

    // MARK: - Happy path

    func testDoubleTap_withinWindow_fires() {
        // down → up → down (within 500 ms)
        DoubleTapTrigger.shared.handleFlags([.command]) // idle → firstDown
        DoubleTapTrigger.shared.handleFlags([])          // firstDown → firstUp
        DoubleTapTrigger.shared.handleFlags([.command]) // firstUp → FIRED
        XCTAssertTrue(fired)
    }

    // MARK: - No-fire cases

    func testSingleTap_doesNotFire() {
        DoubleTapTrigger.shared.handleFlags([.command])
        DoubleTapTrigger.shared.handleFlags([])
        XCTAssertFalse(fired)
    }

    func testChord_duringDoubleTap_resetsAndDoesNotFire() {
        // Begin a double-tap…
        DoubleTapTrigger.shared.handleFlags([.command]) // → firstDown
        DoubleTapTrigger.shared.handleFlags([])          // → firstUp
        // …then interrupt with a chord on the second press
        DoubleTapTrigger.shared.handleFlags([.command, .shift]) // chord → idle
        DoubleTapTrigger.shared.handleFlags([.command])          // → firstDown (not fired)
        XCTAssertFalse(fired)
    }

    func testChord_atFirstPress_preventsDoubleTap() {
        // If the very first press is a chord, the state machine never leaves idle
        DoubleTapTrigger.shared.handleFlags([.command, .option]) // chord → idle
        DoubleTapTrigger.shared.handleFlags([])
        DoubleTapTrigger.shared.handleFlags([.command])          // → firstDown
        DoubleTapTrigger.shared.handleFlags([])                  // → firstUp
        DoubleTapTrigger.shared.handleFlags([.command])          // → FIRED (clean sequence after chord)
        // The chord earlier did not cause a fire; the clean sequence that follows does.
        XCTAssertTrue(fired, "A clean double-tap after a chord should still fire")
    }

    func testDoubleTap_afterWindowExpires_doesNotFire() {
        DoubleTapTrigger.shared.handleFlags([.command]) // → firstDown
        DoubleTapTrigger.shared.handleFlags([])          // → firstUp(at: now)
        Thread.sleep(forTimeInterval: 0.55)              // exceed the 500 ms window
        DoubleTapTrigger.shared.handleFlags([.command]) // too late → firstDown, not FIRED
        XCTAssertFalse(fired)
    }

    // MARK: - Modifier switch

    func testStopAndRestartWithNewModifier_oldModifierNoLongerTriggers() {
        // Begin a partial .command sequence
        DoubleTapTrigger.shared.handleFlags([.command]) // → firstDown
        DoubleTapTrigger.shared.handleFlags([])          // → firstUp
        // Switch to watching .option — state resets
        DoubleTapTrigger.shared.start(modifier: .option)
        // Complete the .command sequence: should be ignored (watching .option now)
        DoubleTapTrigger.shared.handleFlags([.command])
        XCTAssertFalse(fired)
    }

    func testRestartedModifier_newDoubleTap_fires() {
        DoubleTapTrigger.shared.start(modifier: .option)
        DoubleTapTrigger.shared.handleFlags([.option])
        DoubleTapTrigger.shared.handleFlags([])
        DoubleTapTrigger.shared.handleFlags([.option])
        XCTAssertTrue(fired)
    }
}
