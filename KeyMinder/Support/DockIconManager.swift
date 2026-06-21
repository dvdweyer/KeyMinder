// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Tracks how many "dock-visible" windows (Settings, About) are open and
/// switches the activation policy accordingly: .regular while any are open
/// (so a Dock icon and app menu appear), .accessory when all are closed.
@MainActor
final class DockIconManager {
    static let shared = DockIconManager()
    private var openCount = 0

    func windowOpened() {
        openCount += 1
        if openCount == 1 {
            NSApp.setActivationPolicy(.regular)
            UserDefaults.standard.appIconVariant.apply()
        }
    }

    func windowClosed() {
        openCount = max(0, openCount - 1)
        if openCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
