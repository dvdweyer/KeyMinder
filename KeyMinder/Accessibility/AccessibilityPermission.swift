// SPDX-License-Identifier: GPL-3.0-or-later
import ApplicationServices
import AppKit

/// Thin wrapper around the Accessibility-trust APIs that KeyMinder needs in order
/// to read other applications' menus.
enum AccessibilityPermission {

    /// Whether this process is currently trusted for Accessibility.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the system prompt that offers to open Privacy settings, and
    /// registers KeyMinder in the Accessibility list. Returns the current trust
    /// state (typically `false` on first call).
    @discardableResult
    static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings directly at Privacy & Security › Accessibility.
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
