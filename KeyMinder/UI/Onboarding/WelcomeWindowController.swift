import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController {

    static let shared = WelcomeWindowController()

    /// Fires when the wizard closes for any reason: Done, Skip, or the title-bar ✕.
    var onDismiss: (() -> Void)?

    /// Fires when the user taps "Try it now" in the trigger step.
    /// AppDelegate wires this to `presentPopup()`.
    var onTryItNow: (() -> Void)?

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
        let rootView = WelcomeView(
            onTryItNow: { [weak self] in self?.onTryItNow?() },
            onDismiss:  { [weak self] in self?.window?.close() }
        )
        window?.contentView = NSHostingView(rootView: rootView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension WelcomeWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onDismiss?()
        onDismiss = nil
    }
}
