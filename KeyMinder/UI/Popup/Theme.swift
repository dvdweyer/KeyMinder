import SwiftUI

/// Centralized colors/metrics so the popup's look (and the screenshot-style green
/// accent) can be tuned in one place. All colors are semantic or system colors,
/// so light and dark mode are handled automatically.
enum Theme {
    /// Color used for the key combination glyphs (the green in the reference design).
    static let keyAccent = Color(nsColor: .systemGreen)

    /// Background fill behind a menu's section header bar.
    static let sectionHeaderFill = Color.primary.opacity(0.06)

    static let keyColumnWidth: CGFloat = 86
    static let cornerRadius: CGFloat = 16
    static let contentPadding: CGFloat = 16
}
