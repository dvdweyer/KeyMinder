// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Persists the user's pinned shortcuts across sessions.
///
/// A shortcut is identified by `appID|title|keys` — stable across re-scrapes
/// because title and key string are derived from the menu item itself, not
/// from the ephemeral AX element or the Shortcut's per-scrape UUID.
/// `appID` is the app's bundle identifier, falling back to its display name
/// for the rare app that ships without one.
@Observable @MainActor
final class FavouritesStore {
    static let shared = FavouritesStore()
    private static let defaultsKey = "pinnedShortcuts"
    private var pinned: Set<String>

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        pinned = Set(stored)
    }

    func isFavourite(_ shortcut: Shortcut, appID: String) -> Bool {
        let k = key(for: shortcut, appID: appID)
        if pinned.contains(k) { return true }
        // Fall back to the pre-v1.0.185 unescaped key format: a field containing a
        // literal "|" makes the stored string ambiguous to un-split, so old entries
        // are never parsed/migrated up front — only matched here on lookup and
        // opportunistically converged to the new format once found.
        let legacy = legacyKey(for: shortcut, appID: appID)
        guard pinned.contains(legacy) else { return false }
        pinned.remove(legacy)
        pinned.insert(k)
        UserDefaults.standard.set(Array(pinned), forKey: Self.defaultsKey)
        return true
    }

    func toggle(_ shortcut: Shortcut, appID: String) {
        let k = key(for: shortcut, appID: appID)
        if pinned.contains(k) { pinned.remove(k) } else { pinned.insert(k) }
        UserDefaults.standard.set(Array(pinned), forKey: Self.defaultsKey)
    }

    func hasFavourites(for appID: String) -> Bool {
        let prefix = Self.esc(appID) + "|"
        let legacyPrefix = appID + "|"
        return pinned.contains { $0.hasPrefix(prefix) || $0.hasPrefix(legacyPrefix) }
    }

    func reload() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        pinned = Set(stored)
    }

    private static func esc(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "||") }

    private func key(for shortcut: Shortcut, appID: String) -> String {
        "\(Self.esc(appID))|\(Self.esc(shortcut.title))|\(Self.esc(shortcut.keys))"
    }

    private func legacyKey(for shortcut: Shortcut, appID: String) -> String {
        "\(appID)|\(shortcut.title)|\(shortcut.keys)"
    }
}
