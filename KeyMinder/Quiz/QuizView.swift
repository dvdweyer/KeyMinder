// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

// MARK: - Model

enum QuizPhase: Equatable {
    case asking
    case correct
    case wrong(pressedKeys: String)
    case done
}

struct QuizQuestion {
    let title: String
    let keys: String
    let menuTitle: String
}

@Observable @MainActor
final class QuizModel {
    private let allQuestions: [QuizQuestion]
    private let bundleID: String?
    private(set) var activeQuestions: [QuizQuestion]
    private(set) var currentIndex = 0
    private(set) var score = 0
    private(set) var phase: QuizPhase = .asking
    let appName: String
    let appIcon: NSImage?
    let hasFavourites: Bool

    var favouritesOnly: Bool = false {
        didSet { applyFilter() }
    }

    var current: QuizQuestion? {
        guard currentIndex < activeQuestions.count else { return nil }
        return activeQuestions[currentIndex]
    }
    var total: Int { activeQuestions.count }

    init(sections: [MenuSection], appName: String, appIcon: NSImage?, bundleID: String?) {
        self.appName = appName
        self.appIcon = appIcon
        self.bundleID = bundleID
        var qs: [QuizQuestion] = []
        for section in sections {
            for group in section.groups {
                for shortcut in group.shortcuts
                    where !shortcut.keys.isEmpty && !shortcut.isSeparator {
                    qs.append(QuizQuestion(title: shortcut.title,
                                          keys: shortcut.keys,
                                          menuTitle: section.title))
                }
            }
        }
        self.allQuestions = qs
        self.activeQuestions = qs.shuffled()
        if let bundleID {
            hasFavourites = qs.contains { q in
                FavouritesStore.shared.isFavourite(Shortcut(title: q.title, keys: q.keys), appID: bundleID)
            }
        } else {
            hasFavourites = false
        }
    }

    func checkAnswer(_ keys: String) {
        guard case .asking = phase, let current else { return }
        if keys == current.keys {
            score += 1
            phase = .correct
        } else {
            phase = .wrong(pressedKeys: keys)
        }
    }

    func advance() {
        currentIndex += 1
        phase = currentIndex >= activeQuestions.count ? .done : .asking
    }

    func restart() { applyFilter() }

    private func applyFilter() {
        guard let bundleID else { return }
        let pool: [QuizQuestion]
        if favouritesOnly {
            pool = allQuestions.filter { q in
                FavouritesStore.shared.isFavourite(Shortcut(title: q.title, keys: q.keys), appID: bundleID)
            }
        } else {
            pool = allQuestions
        }
        activeQuestions = pool.shuffled()
        currentIndex = 0
        score = 0
        phase = activeQuestions.isEmpty ? .done : .asking
    }
}

// MARK: - Root view

struct QuizView: View {
    var model: QuizModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            QuizHeaderView(model: model)
            Divider()
            if case .done = model.phase {
                QuizDoneView(model: model, onDone: onDone)
            } else {
                QuizQuestionView(model: model)
            }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - Header

private struct QuizHeaderView: View {
    var model: QuizModel

    var body: some View {
        HStack(spacing: 8) {
            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(model.appName)
                .fontWeight(.medium)
            Spacer()
            if model.hasFavourites {
                Button {
                    model.favouritesOnly.toggle()
                } label: {
                    Image(systemName: model.favouritesOnly ? "star.fill" : "star")
                        .foregroundStyle(model.favouritesOnly ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(model.favouritesOnly ? "Showing favourites only" : "Quiz favourites only")
            }
            if case .done = model.phase {
                Text("Complete")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.currentIndex + 1) / \(model.total)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Question

private struct QuizQuestionView: View {
    var model: QuizModel

    private var wrongCount: Int { model.currentIndex - model.score }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(model.currentIndex), total: Double(max(1, model.total)))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Spacer()

            if let q = model.current {
                VStack(spacing: 8) {
                    Text("in \(q.menuTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(q.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            answerArea
                .frame(height: 56)

            Spacer()

            HStack {
                Text("\(model.score) correct · \(wrongCount) wrong")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var answerArea: some View {
        switch model.phase {
        case .asking:
            Text("Press the shortcut…")
                .foregroundStyle(.tertiary)
        case .correct:
            if let q = model.current {
                Label(q.keys, systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
            }
        case .wrong(let pressed):
            if let q = model.current {
                VStack(spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("You pressed \(pressed)").foregroundStyle(.red)
                    }
                    Text("Correct: \(q.keys)").foregroundStyle(.secondary)
                }
                .font(.body.weight(.medium))
            }
        case .done:
            EmptyView()
        }
    }
}

// MARK: - Done screen

private struct QuizDoneView: View {
    var model: QuizModel
    var onDone: () -> Void

    private var percentage: Int {
        guard model.total > 0 else { return 0 }
        return Int(Double(model.score) / Double(model.total) * 100)
    }

    private var symbol: String {
        percentage >= 80 ? "star.fill" : percentage >= 50 ? "hand.thumbsup.fill" : "brain.fill"
    }

    private var symbolColor: Color {
        percentage >= 80 ? .yellow : .secondary
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(symbolColor)

            VStack(spacing: 4) {
                Text("\(model.score) / \(model.total)")
                    .font(.title.weight(.bold))
                Text("\(percentage)% correct")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Quiz Again") { model.restart() }
                    .keyboardShortcut(.defaultAction)
                Button("Done", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 24)
        }
    }
}
