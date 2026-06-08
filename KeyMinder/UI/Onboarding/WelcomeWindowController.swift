import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController {

    static let shared = WelcomeWindowController()

    /// Fires when the wizard is completed (Done on the last step).
    /// AppDelegate uses this to mark the wizard as done and open the popup.
    var onComplete: (() -> Void)?

    /// Fires when the user taps "Try it now" in the trigger step.
    var onTryItNow: (() -> Void)?

    private var wizardCompleted = false
    private var isTerminating   = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        window.title = String(localized: "Welcome to KeyMinder",
                              comment: "Welcome wizard window title")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        wizardCompleted = false
        isTerminating   = false
        let rootView = WelcomeView(
            onTryItNow: { [weak self] in self?.onTryItNow?() },
            onComplete: { [weak self] in
                self?.wizardCompleted = true
                self?.window?.close()
            },
            onQuit: { [weak self] in
                guard let self, !self.isTerminating else { return }
                self.isTerminating = true
                NSApp.terminate(nil)
            }
        )
        window?.contentView = NSHostingView(rootView: rootView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension WelcomeWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if wizardCompleted {
            onComplete?()
            onComplete = nil
        } else if !isTerminating {
            // Closed via the title-bar ✕ — treat as quit.
            isTerminating = true
            NSApp.terminate(nil)
        }
    }
}
