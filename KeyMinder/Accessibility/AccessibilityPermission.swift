// SPDX-License-Identifier: GPL-3.0-or-later
import ApplicationServices
import AppKit
import os

/// Thin wrapper around the Accessibility-trust APIs that KeyMinder needs in order
/// to read other applications' menus.
enum AccessibilityPermission {

    /// macOS 27.3 moved the right to read and control other apps out of Accessibility
    /// into "System & App Protection Override". The user adds KeyMinder there with +
    /// and chooses full access or a per-app list ("Ask First" / "At Any Time").
    static let usesAppProtectionOverride = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 3, patchVersion: 0))

    /// Whether this process is trusted. On 27.3+ this is true as soon as KeyMinder is in
    /// the Override list, even with per-app access to no app at all; `access(to:)` tells
    /// whether a particular app can be read.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Result of probing one app.
    enum AppAccess: Equatable {
        case granted
        /// macOS refused the read (`kAXErrorAPIDisabled`). On 27.3+ with per-app access,
        /// this also triggers macOS's "Allow KeyMinder to temporarily control …?" prompt
        /// for apps set to "Ask First".
        case denied
        /// Any other failure (no menu bar, app busy, …): not a permission problem.
        case unavailable
    }

    /// Probes whether KeyMinder may read the app with `pid`, by reading its menu bar.
    /// Blocking AX IPC (up to the 1 s messaging timeout); call off the main thread.
    nonisolated static func access(to pid: pid_t) -> AppAccess {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) {
        case .success: return .granted
        case .apiDisabled: return .denied
        default: return .unavailable
        }
    }

    /// Before 27.3: triggers the system prompt that offers to open Privacy settings and
    /// registers KeyMinder in the Accessibility list. On 27.3+ that prompt shows nothing
    /// and registers nothing, so this opens the Override pane instead. Returns the
    /// current trust state (typically `false` on first call).
    @discardableResult
    static func requestAccess() -> Bool {
        if usesAppProtectionOverride {
            openSettings()
            return isTrusted
        }
        // The value of kAXTrustedCheckOptionPrompt; the imported global is a mutable
        // `var`, which strict concurrency checking rejects.
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings at Privacy & Security › Accessibility, which on 27.3+ is
    /// "System & App Protection Override" (the new assistive-technology Accessibility
    /// pane is `Privacy_AccessibilityApps`).
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
