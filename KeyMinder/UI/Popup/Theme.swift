import SwiftUI

/// Centralized colors/metrics so the popup's look (and the screenshot-style green
/// accent) can be tuned in one place. All colors are semantic or system colors,
/// so light and dark mode are handled automatically.
enum Theme {
    /// Color used for the key combination glyphs.
    /// A dark forest-green in light mode; a lighter mint in dark mode for contrast.
    static let keyAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.45, alpha: 1)  // dark mode: bright mint
            : NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.15, alpha: 1)  // light mode: dark forest green
    })

    /// Background fill behind a menu's section header bar.
    static let sectionHeaderFill = Color.primary.opacity(0.06)

    static let keyColumnWidth: CGFloat = 86
    static let cornerRadius: CGFloat = 16
    static let contentPadding: CGFloat = 16
}
