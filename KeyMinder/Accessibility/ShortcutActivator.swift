// SPDX-License-Identifier: GPL-3.0-or-later
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
    ///
    /// Before pressing, re-reads `kAXEnabledAttribute` to skip items that have
    /// become disabled since the scrape, and re-reads `kAXTitleAttribute` so that
    /// any label mismatch between the displayed title and the live element is
    /// logged. This closes the false-label-press vector where a hostile app could
    /// change its menu item's title after the popup was shown.
    @discardableResult
    static func activate(_ shortcut: Shortcut) -> Bool {
        guard let element = shortcut.axElement else { return false }

        // Re-read enabled state at press time — an item may have been disabled
        // after the popup was opened.
        var enabledRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success,
           let enabledNum = enabledRef as? NSNumber,
           !enabledNum.boolValue {
            Logger.accessibility.info("Skipping press — item '\(shortcut.title, privacy: .private)' is now disabled")
            return false
        }

        // Re-read the live title and log if it no longer matches what the popup showed.
        // shortcut.title was sanitized at the scrape boundary (MenuScraper.titleString),
        // so the raw live AX string must be sanitized the same way before comparing —
        // otherwise any title altered by sanitization (over 256 graphemes, bidi marks,
        // control chars, non-NFC) would log a spurious mismatch on every activation.
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let liveTitle = titleRef as? String,
           ScrapedStringPolicy.sanitize(liveTitle) != shortcut.title {
            Logger.accessibility.error(
                "Title mismatch at press: displayed '\(shortcut.title, privacy: .private)' but live element is '\(liveTitle, privacy: .private)'"
            )
        }

        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            Logger.accessibility.error("AX press failed for '\(shortcut.title, privacy: .private)'")
        }
        return result == .success
    }
}
