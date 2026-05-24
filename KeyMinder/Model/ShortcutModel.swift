import Foundation
import AppKit

/// A single keyboard shortcut: the menu item that triggers it and the
/// formatted key combination (e.g. "⇧⌘N").
struct Shortcut: Identifiable, Hashable {
    let id = UUID()
    /// The menu item's title, e.g. "New Conversation".
    let title: String
    /// The display string for the key combination, e.g. "⇧⌘N".
    let keys: String
}

/// A flat list of shortcuts within a `MenuSection`, optionally named after the
/// submenu they came from.
///
/// - `title == nil`: top-level items scraped directly from the menu (no submenu header shown).
/// - `title != nil`: items scraped from a submenu; the title is rendered as a sub-header.
struct ShortcutGroup: Identifiable, Hashable {
    let id = UUID()
    /// Submenu name, e.g. "Move & Resize". `nil` for top-level (non-submenu) items.
    let title: String?
    let shortcuts: [Shortcut]
}

/// A group of shortcuts that share a top-level menu, e.g. "File" or "Edit".
/// Internally organised into `ShortcutGroup`s — one unnamed group for top-level
/// items plus one named group per submenu.
struct MenuSection: Identifiable, Hashable {
    let id = UUID()
    /// The top-level menu title, e.g. "File".
    let title: String
    let groups: [ShortcutGroup]

    /// All shortcuts across every group, in order. Convenience for callers that
    /// don't need to distinguish groups (e.g. counts, isEmpty checks).
    var shortcuts: [Shortcut] { groups.flatMap(\.shortcuts) }
}

/// The full set of shortcuts scraped for one application.
struct AppShortcuts {
    let appName: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let sections: [MenuSection]

    var isEmpty: Bool { sections.allSatisfy { $0.shortcuts.isEmpty } }

    var totalCount: Int { sections.reduce(0) { $0 + $1.shortcuts.count } }
}

/// What the popup should display.
enum PopupContent {
    case shortcuts(AppShortcuts)
    case needsPermission
    case noApp
}
