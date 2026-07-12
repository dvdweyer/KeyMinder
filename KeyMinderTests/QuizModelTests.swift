// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import KeyMinder

@MainActor
final class QuizModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeShortcut(title: String, keys: String) -> Shortcut {
        Shortcut(title: title, keys: keys)
    }

    private func makeSection(_ title: String, shortcuts: [Shortcut]) -> MenuSection {
        MenuSection(title: title, groups: [ShortcutGroup(title: nil, shortcuts: shortcuts)])
    }

    private func makeModel(questionCount: Int = 3) -> QuizModel {
        let shortcuts = (0..<questionCount).map {
            makeShortcut(title: "Command \($0)", keys: "⌘\($0)")
        }
        let section = makeSection("File", shortcuts: shortcuts)
        return QuizModel(sections: [section], appName: "TestApp", appIcon: nil, bundleID: nil)
    }

    // MARK: - checkAnswer

    func testCheckAnswer_correctKeys_scoresAndSetsCorrectPhase() {
        let model = makeModel()
        let answer = model.current!.keys
        model.checkAnswer(answer)
        XCTAssertEqual(model.phase, .correct)
        XCTAssertEqual(model.score, 1)
    }

    func testCheckAnswer_wrongKeys_setsWrongPhaseWithoutScoring() {
        let model = makeModel()
        model.checkAnswer("⌘Z-not-a-real-answer")
        XCTAssertEqual(model.phase, .wrong(pressedKeys: "⌘Z-not-a-real-answer"))
        XCTAssertEqual(model.score, 0)
    }

    func testCheckAnswer_ignoredWhenNotAsking() {
        let model = makeModel()
        model.checkAnswer(model.current!.keys)
        XCTAssertEqual(model.phase, .correct)
        // A second checkAnswer call while not in .asking must not re-score.
        model.checkAnswer(model.current!.keys)
        XCTAssertEqual(model.score, 1)
    }

    // MARK: - advance sequencing

    func testAdvance_movesToNextQuestionAndResetsToAsking() {
        let model = makeModel(questionCount: 2)
        XCTAssertEqual(model.currentIndex, 0)
        model.checkAnswer(model.current!.keys)
        model.advance()
        XCTAssertEqual(model.currentIndex, 1)
        XCTAssertEqual(model.phase, .asking)
    }

    func testAdvance_pastLastQuestionSetsDonePhase() {
        let model = makeModel(questionCount: 1)
        model.checkAnswer(model.current!.keys)
        model.advance()
        XCTAssertEqual(model.currentIndex, 1)
        XCTAssertEqual(model.phase, .done)
    }

    func testAdvance_calledTwiceFromAskingDoesNotSkipPastDone() {
        // Regression for the double-advance bug: a second advance() call after
        // reaching .done (e.g. from a cancelled auto-advance task racing a manual
        // skip) must not push currentIndex further out of bounds.
        let model = makeModel(questionCount: 1)
        model.checkAnswer(model.current!.keys)
        model.advance()
        XCTAssertEqual(model.currentIndex, 1)
        XCTAssertEqual(model.phase, .done)
        model.advance()
        XCTAssertEqual(model.currentIndex, 1)
        XCTAssertEqual(model.phase, .done)
    }
}
