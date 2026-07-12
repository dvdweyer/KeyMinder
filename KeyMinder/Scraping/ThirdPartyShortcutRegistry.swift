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
///
/// The Integrations directory is writable by any same-user process, so every
/// string crossing this boundary goes through `ScrapedStringPolicy.sanitize`
/// (same policy as AX titles and `NSUserKeyEquivalents`), and the number of
/// shortcuts read per file is capped.
enum ThirdPartyShortcutRegistry {

    /// Shortcuts beyond this count in a single registration file are dropped.
    static let maxShortcutsPerFile = 500

    /// Files larger than this are skipped without being read. `maxShortcutsPerFile`
    /// only caps decoded entries *after* the whole file is read into memory, so
    /// without this a pathological multi-hundred-MB `.json` in the user-writable
    /// Integrations directory would be read fully before being rejected.
    static let maxFileBytes = 1_048_576  // 1 MB

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
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileBytes {
                Logger.scraper.info("ThirdPartyRegistry: skipping oversized \(url.lastPathComponent, privacy: .public)")
                return nil
            }
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

        for s in file.shortcuts.prefix(maxShortcutsPerFile) {
            let shortcut = Shortcut(
                title: ScrapedStringPolicy.sanitize(s.title),
                keys: ScrapedStringPolicy.sanitize(s.keys)
            )
            if let groupName = s.group.map(ScrapedStringPolicy.sanitize) {
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
        return MenuSection(title: ScrapedStringPolicy.sanitize(file.appName), groups: groups)
    }
}
