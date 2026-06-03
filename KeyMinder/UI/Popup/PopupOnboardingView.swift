import SwiftUI

/// Shown in the popup when KeyMinder doesn't yet have Accessibility permission.
struct PopupOnboardingView: View {
    var onGrant: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "accessibility")
                .font(.system(size: 40))
                .foregroundStyle(ThemeSettings.shared.keyAccent)

            Text("KeyMinder needs Accessibility access")
                .font(.headline)

            Text("KeyMinder reads the active app's menus to show its keyboard shortcuts. "
                 + "Grant access in Privacy & Security — the popup will update automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Grant Access…", action: onGrant)
                    .buttonStyle(.borderedProminent)
                Button("Open Settings…", action: onOpenSettings)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
