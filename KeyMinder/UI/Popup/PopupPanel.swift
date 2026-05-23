import AppKit

/// A borderless, non-activating floating panel that can still become key (so it
/// can receive the Esc keystroke) without stealing activation from the app the
/// user is actually working in.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
