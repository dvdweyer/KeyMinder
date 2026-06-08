import Foundation
import AppKit
import ApplicationServices

/// A single keyboard shortcut: the menu item that triggers it and the
/// formatted key combination (e.g. "⇧⌘N").
struct Shortcut: Identifiable, Hashable {
    let id = UUID()
    /// The menu item's title, e.g. "New Conversation".
    let title: String
    /// The display string for the key combination, e.g. "⇧⌘N".
    let keys: String
    /// The AX element for this menu item. Used to activate the shortcut
    /// via `AXUIElementPerformAction`. `nil` only for synthetic/test instances.
    let axElement: AXUIElement?
    /// True for system shortcuts the user has explicitly disabled. Such rows
    /// are always rendered dimmed and excluded from Tab navigation.
    let isDisabled: Bool

    // AXUIElement is a CFTypeRef (opaque class) and can't participate in
    // automatic Hashable synthesis. Identity is fully determined by the UUID.
    static func == (lhs: Shortcut, rhs: Shortcut) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Shortcut {
    /// Convenience init for tests and other call sites that don't have an AX element.
    init(title: String, keys: String) {
        self.title = title
        self.keys = keys
        self.axElement = nil
        self.isDisabled = false
    }

    init(title: String, keys: String, isDisabled: Bool) {
        self.title = title
        self.keys = keys
        self.axElement = nil
        self.isDisabled = isDisabled
    }
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
    /// True when the scrape included items without key equivalents (all-entries mode).
    let includesItemsWithoutShortcuts: Bool

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
        // Empty query matches everything — `localizedStandardContains("")` returns
        // false (Foundation does not treat an empty needle as "found anywhere"),
        // so we guard explicitly. The view layers already short-circuit on
        // `!query.isEmpty` before calling this, so the guard is defence-in-depth.
        query.isEmpty
            || title.localizedStandardContains(query)
            || keys.localizedStandardContains(query)
    }

    /// The set of modifier glyphs present in this shortcut's key string.
    var modifiers: Set<Character> {
        Set(keys.filter { Self.modifierGlyphs.contains($0) })
    }

    /// True when `mods` is empty (no filter) or exactly equals this shortcut's modifier set.
    func matchesModifierFilter(_ mods: Set<Character>) -> Bool {
        mods.isEmpty || modifiers == mods
    }

    static let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
}

extension ShortcutGroup {
    func hasMatch(_ query: String) -> Bool { shortcuts.contains { $0.matches(query) } }
}

extension MenuSection {
    func hasMatch(_ query: String) -> Bool { groups.contains { $0.hasMatch(query) } }
}

extension AppShortcuts {
    /// Number of shortcuts matching `query`.
    ///
    /// Uses a nested `reduce` rather than `filter { }.count` to avoid
    /// allocating a temporary `[Shortcut]` array per section just to
    /// discard it after counting its elements.
    func matchCount(_ query: String) -> Int {
        sections.reduce(0) { total, section in
            total + section.shortcuts.reduce(0) { $0 + ($1.matches(query) ? 1 : 0) }
        }
    }

    /// Key strings that are assigned to two or more shortcuts in this app.
    /// Empty key strings (all-entries mode items with no binding) are excluded.
    var conflictingKeys: Set<String> {
        var tally: [String: Int] = [:]
        for shortcut in sections.flatMap(\.shortcuts) where !shortcut.keys.isEmpty {
            tally[shortcut.keys, default: 0] += 1
        }
        return Set(tally.filter { $0.value > 1 }.keys)
    }
}
