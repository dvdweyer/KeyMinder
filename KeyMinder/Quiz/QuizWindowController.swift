// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor
final class QuizWindowController: NSWindowController, NSWindowDelegate {

    private static var current: QuizWindowController?
    private var keyMonitor: Any?
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
        let window = NSWindow(
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
        installKeyMonitor(model: model)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func installKeyMonitor(model: QuizModel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event: event, model: model) ?? event }
        }
    }

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
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        QuizWindowController.current = nil
        DockIconManager.shared.windowClosed()
    }
}
