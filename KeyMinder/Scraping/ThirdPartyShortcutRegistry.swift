// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import os

/// Loads third-party app shortcut registrations from
/// `~/Library/Application Support/KeyMinder/Integrations/<BundleID>.json`
/// and returns them as `MenuSection`s ready to append to the popup.
///
/// **Registration format** — write a JSON file at the path above:
/// ```json
/// {
///   "version": 1,
///   "appName": "Raycast",
///   "bundleIdentifier": "com.raycast.macos",
///   "shortcuts": [
///     { "title": "Show Raycast",     "keys": "⌥Space",  "group": "General" },
///     { "title": "Show File Search", "keys": "⌥⇧Space", "group": "General" },
///     { "title": "Show Clipboard",   "keys": "⌥⌘C" }
///   ]
/// }
/// ```
/// `keys` is a display-format glyph string (⌥Space, ⇧⌘K, etc.) rendered as-is
/// in the popup key badge. `group` is optional; omit it for ungrouped items.
/// Malformed or unreadable files are skipped and logged at `.info`.
enum ThirdPartyShortcutRegistry {

    private struct RegistrationFile: Decodable {
        let appName: String
        let shortcuts: [RegisteredShortcut]
    }

    private struct RegisteredShortcut: Decodable {
        let title: String
        let keys: String
        let group: String?
    }

    /// Reads all `.json` files from the Integrations directory and returns one
    /// `MenuSection` per registered app. Returns `[]` when the directory is
    /// absent, empty, or contains only malformed files.
    static func load() -> [MenuSection] {
        guard let dir = integrationsDirectory() else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        let jsonFiles = entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !jsonFiles.isEmpty else { return [] }

        return jsonFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else {
                Logger.scraper.info("ThirdPartyRegistry: unreadable \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            guard let file = try? JSONDecoder().decode(RegistrationFile.self, from: data) else {
                Logger.scraper.info("ThirdPartyRegistry: malformed \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            return section(from: file)
        }
    }

    // MARK: - Private

    private static func integrationsDirectory() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = support.appendingPathComponent("KeyMinder/Integrations", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    private static func section(from file: RegistrationFile) -> MenuSection {
        var unnamedShortcuts: [Shortcut] = []
        var namedGroups: [(name: String, shortcuts: [Shortcut])] = []
        var namedIndex: [String: Int] = [:]

        for s in file.shortcuts {
            let shortcut = Shortcut(title: s.title, keys: s.keys)
            if let groupName = s.group {
                if let idx = namedIndex[groupName] {
                    namedGroups[idx].shortcuts.append(shortcut)
                } else {
                    namedIndex[groupName] = namedGroups.count
                    namedGroups.append((groupName, [shortcut]))
                }
            } else {
                unnamedShortcuts.append(shortcut)
            }
        }

        var groups: [ShortcutGroup] = []
        if !unnamedShortcuts.isEmpty {
            groups.append(ShortcutGroup(title: nil, shortcuts: unnamedShortcuts))
        }
        for (name, shortcuts) in namedGroups {
            groups.append(ShortcutGroup(title: name, shortcuts: shortcuts))
        }
        return MenuSection(title: file.appName, groups: groups)
    }
}
