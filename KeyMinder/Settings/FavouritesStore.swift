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
        pinned.contains(key(for: shortcut, appID: appID))
    }

    func toggle(_ shortcut: Shortcut, appID: String) {
        let k = key(for: shortcut, appID: appID)
        if pinned.contains(k) { pinned.remove(k) } else { pinned.insert(k) }
        UserDefaults.standard.set(Array(pinned), forKey: Self.defaultsKey)
    }

    func hasFavourites(for appID: String) -> Bool {
        let prefix = appID + "|"
        return pinned.contains { $0.hasPrefix(prefix) }
    }

    func reload() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        pinned = Set(stored)
    }

    private func key(for shortcut: Shortcut, appID: String) -> String {
        "\(appID)|\(shortcut.title)|\(shortcut.keys)"
    }
}
