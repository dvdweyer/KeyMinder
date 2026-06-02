import ApplicationServices
import os

/// Activates a scraped menu-item shortcut by performing the AX press action
/// on its stored element reference.
enum ShortcutActivator {

    /// Tells the target app to execute `shortcut`'s menu item.
    ///
    /// Returns `true` on success. The common failure case is a stale element
    /// (the target app rebuilt its menu after the scrape), which is rare in
    /// practice because most apps keep their `NSMenu` objects alive indefinitely.
    @discardableResult
    static func activate(_ shortcut: Shortcut) -> Bool {
        guard let element = shortcut.axElement else { return false }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            Logger.accessibility.error("AX press failed for '\(shortcut.title, privacy: .private)'")
        }
        return result == .success
    }
}
