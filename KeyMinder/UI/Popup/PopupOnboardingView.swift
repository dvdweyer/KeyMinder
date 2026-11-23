// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Shown in the popup when KeyMinder doesn't yet have Accessibility permission, or
/// (macOS 27.3+, `blockedAppName` set) when it may not read the active app.
struct PopupOnboardingView: View {
    /// Name of the app macOS refused access to; `nil` when KeyMinder isn't trusted at all.
    var blockedAppName: String? = nil
    var onGrant: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "accessibility")
                .font(.system(size: 40))
                .foregroundStyle(ThemeSettings.shared.keyAccent)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if AccessibilityPermission.usesAppProtectionOverride {
                    Button("Open System Settings…", action: onGrant)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Grant Access…", action: onGrant)
                        .buttonStyle(.borderedProminent)
                    Button("Open Settings…", action: onOpenSettings)
                }
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if let blockedAppName {
            return String(localized: "KeyMinder can’t read \(blockedAppName)")
        }
        return AccessibilityPermission.usesAppProtectionOverride
            ? String(localized: "KeyMinder needs access to your apps")
            : String(localized: "KeyMinder needs Accessibility access")
    }

    private var message: String {
        if let blockedAppName {
            return String(localized: "Allow KeyMinder to control \(blockedAppName) when macOS asks, or give KeyMinder full access in Privacy & Security → System & App Protection Override. The popup will update automatically.")
        }
        return AccessibilityPermission.usesAppProtectionOverride
            ? String(localized: "KeyMinder reads the active app’s menus to show its keyboard shortcuts. In Privacy & Security → System & App Protection Override, add KeyMinder with + and choose Override System Protections. The popup will update automatically.")
            : String(localized: "KeyMinder reads the active app's menus to show its keyboard shortcuts. Grant access in Privacy & Security — the popup will update automatically.")
    }
}
