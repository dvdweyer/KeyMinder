// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

// Intercepts key events via sendEvent so no @Sendable closure is needed.
@MainActor
private final class QuizWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let handler = onKeyDown, handler(event) {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class QuizWindowController: NSWindowController, NSWindowDelegate {

    private static var current: QuizWindowController?
    private var advanceTask: Task<Void, Never>?

    static func show(appName: String, appIcon: NSImage?, bundleID: String?, sections: [MenuSection]) {
        let model = QuizModel(sections: sections, appName: appName, appIcon: appIcon, bundleID: bundleID)
        guard model.total > 0 else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Nothing to quiz")
            alert.informativeText = String(localized: "\(appName) has no keyboard shortcuts to quiz.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return
        }
        current?.close()
        current = QuizWindowController(model: model)
        DockIconManager.shared.windowOpened()
        NSApp.activate()
        current?.window?.makeKeyAndOrderFront(nil)
        current?.window?.orderFrontRegardless()
    }

    private init(model: QuizModel) {
        let window = QuizWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Quiz Mode — \(model.appName)")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView:
            QuizView(model: model, onDone: { [weak self] in self?.close() })
        )
        window.onKeyDown = { [weak self] event in
            self?.handle(event: event, model: model) == nil
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func handle(event: NSEvent, model: QuizModel) -> NSEvent? {
        if event.keyCode == 53 { close(); return nil }  // Escape

        switch model.phase {
        case .asking:
            guard let formatted = ShortcutFormatter.keys(from: event) else { return event }
            model.checkAnswer(formatted)
            let delay: TimeInterval = model.phase == .correct ? 0.8 : 1.5
            advanceTask = Task { @MainActor [weak self, weak model] in
                try? await Task.sleep(for: .seconds(delay))
                model?.advance()
                self?.advanceTask = nil
            }
            return nil

        case .correct, .wrong:
            // Any key press skips the result and advances immediately.
            // Cancel the pending auto-advance so it doesn't fire a second time.
            advanceTask?.cancel()
            advanceTask = nil
            model.advance()
            return nil

        case .done:
            return event
        }
    }

    func windowWillClose(_ notification: Notification) {
        advanceTask?.cancel()
        advanceTask = nil
        QuizWindowController.current = nil
        DockIconManager.shared.windowClosed()
    }
}
