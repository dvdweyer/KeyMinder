import SwiftUI

/// Centralized colors/metrics for the popup. All colors are semantic or system colors
/// so light and dark mode are handled automatically. The key-badge accent colour is
/// user-configurable via `ThemeSettings.shared.keyAccent`.
enum Theme {

    /// Background fill behind a menu's section header bar.
    static let sectionHeaderFill = Color.primary.opacity(0.06)

    /// Low-contrast text colour for shortcuts that don't match the active filter:
    /// light grey on the light material, dark grey on the dark material, so the
    /// matching rows keep full contrast and clearly stand out.
    static let fadedText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.36, alpha: 1)   // dark mode: dark grey
            : NSColor(white: 0.72, alpha: 1)   // light mode: light grey
    })

    /// Amber colour used for the conflict-warning icon on duplicate key bindings.
    static let conflictAccent = Color.orange

    static let keyColumnWidth: CGFloat = 86
    static let cornerRadius: CGFloat = 16
    static let contentPadding: CGFloat = 16
}
