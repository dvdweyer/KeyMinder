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

// MARK: - Matching

/// A shortcut matches a query if the query appears in either the command title
/// or the formatted key string (e.g. "⌘N"). Matching is case- and
/// diacritic-insensitive and locale-aware (`localizedStandardContains`).
/// The popup keeps every shortcut on screen and only *dims* the non-matches, so
/// these helpers report match state rather than filtering the data.
extension Shortcut {
    func matches(_ query: String) -> Bool {
        title.localizedStandardContains(query) || keys.localizedStandardContains(query)
    }
}

extension ShortcutGroup {
    func hasMatch(_ query: String) -> Bool { shortcuts.contains { $0.matches(query) } }
}

extension MenuSection {
    func hasMatch(_ query: String) -> Bool { groups.contains { $0.hasMatch(query) } }
}

extension AppShortcuts {
    /// Number of shortcuts matching `query`.
    func matchCount(_ query: String) -> Int {
        sections.reduce(0) { $0 + $1.shortcuts.filter { $0.matches(query) }.count }
    }
}
