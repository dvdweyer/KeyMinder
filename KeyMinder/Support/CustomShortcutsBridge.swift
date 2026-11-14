// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import os

/// Hands a menu item off to CustomShortcuts (Houdah Software) so the user can
/// assign or change its keyboard shortcut there.
///
/// Protocol: write an edit-request JSON file into CustomShortcuts'
/// `EditRequests` folder, then activate CustomShortcuts, which picks the
/// request up and preselects the item. KeyMinder never writes into other
/// apps' preferences itself.
enum CustomShortcutsBridge {
    static let bundleIdentifier = "com.houdah.CustomShortcuts"
    static let fileExtension = "customShortcuts"

    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static var isInstalled: Bool { applicationURL != nil }

    /// True when `shortcut` is a real menu item CustomShortcuts can target.
    static func canEdit(_ shortcut: Shortcut) -> Bool {
        !shortcut.isSeparator && shortcut.axElement != nil && !shortcut.parents.isEmpty
    }

    // MARK: - Request format

    struct Request: Encodable, Equatable {
        struct Application: Encodable, Equatable {
            let localizedName: String
            let bundleIdentifier: String
            let shortcuts: [Item]
        }
        struct Item: Encodable, Equatable {
            let title: String
            let parents: [String]
        }
        let version = 1
        let kind = "request"
        let creator: String
        let dateCreated: String
        let applications: [Application]
    }

    /// Builds the JSON payload. Pure, so it can be unit-tested.
    static func requestData(appName: String, bundleID: String, title: String,
                            parents: [String], date: Date = Date(),
                            timeZone: TimeZone = .current,
                            creator: String = Bundle.main.bundleIdentifier ?? "org.afaik.KeyMinder") throws -> Data {
        let request = Request(
            creator: creator,
            dateCreated: timestamp(date, timeZone: timeZone),
            applications: [.init(localizedName: appName, bundleIdentifier: bundleID,
                                 shortcuts: [.init(title: title, parents: parents)])]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(request)
    }

    /// `2023-09-05T18:42:57.657+0200`, the format CustomShortcuts' own files use.
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter.string(from: date)
    }

    static var requestsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("EditRequests", isDirectory: true)
    }

    // MARK: - Sending

    /// Writes the request and activates CustomShortcuts. Returns false when the
    /// request could not be written or CustomShortcuts isn't installed.
    @discardableResult
    static func send(_ shortcut: Shortcut, appName: String, bundleID: String) -> Bool {
        guard let appURL = applicationURL else { return false }
        do {
            let data = try requestData(appName: appName, bundleID: bundleID,
                                       title: shortcut.title, parents: shortcut.parents)
            let dir = requestsDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try data.write(to: file, options: .atomic)
        } catch {
            Logger.integration.error("CustomShortcuts request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                Logger.integration.error("Could not open CustomShortcuts: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }
}
