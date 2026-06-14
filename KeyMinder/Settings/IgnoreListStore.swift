// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftUI

@Observable @MainActor
final class IgnoreListStore {
    static let shared = IgnoreListStore()

    private static let defaultsKey       = "ignoreList"
    private static let didSeedKey        = "didSeedIgnoreList"
    private static let didSeedMenusKey   = "didSeedIgnoredMenus"

    var isEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "ignoreListEnabled") }
    }
    var showWhenFiltering: Bool = false {
        didSet { UserDefaults.standard.set(showWhenFiltering, forKey: "ignoreListShowWhenFiltering") }
    }
    var globalTitles: [String]
    var perApp: [String: [String]]
    var appDisplayNames: [String: String]
    var ignoredApps: [String: String]   // bundleID → displayName
    var ignoredMenuTitles: [String]     // top-level menu names to skip entirely

    var sortedAppIDs: [String] {
        perApp.keys.sorted { (appDisplayNames[$0] ?? $0) < (appDisplayNames[$1] ?? $1) }
    }

    var sortedIgnoredAppIDs: [String] {
        ignoredApps.keys.sorted { (ignoredApps[$0] ?? $0) < (ignoredApps[$1] ?? $1) }
    }

    private init() {
        isEnabled        = UserDefaults.standard.bool(forKey: "ignoreListEnabled")
        showWhenFiltering = UserDefaults.standard.bool(forKey: "ignoreListShowWhenFiltering")

        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(IgnoreData.self, from: data) {
            globalTitles      = stored.globalTitles
            perApp            = stored.perApp
            appDisplayNames   = stored.appDisplayNames
            ignoredApps       = stored.ignoredApps
            ignoredMenuTitles = stored.ignoredMenuTitles
        } else {
            globalTitles      = []
            perApp            = [:]
            appDisplayNames   = [:]
            ignoredApps       = [:]
            ignoredMenuTitles = []
        }

        if !UserDefaults.standard.bool(forKey: Self.didSeedKey) {
            globalTitles = ["Minimize", "Fill", "Centre", "Move & Resize"]
            UserDefaults.standard.set(true, forKey: Self.didSeedKey)
            save()
        }

        if !UserDefaults.standard.bool(forKey: Self.didSeedMenusKey) {
            ignoredMenuTitles = ["Apple"]
            UserDefaults.standard.set(true, forKey: Self.didSeedMenusKey)
            save()
        }
    }

    /// Returns the patterns (exact titles or `*`/`?` wildcard globs) to suppress
    /// for a given app. Includes global patterns plus any app-specific ones.
    func ignoredTitles(for bundleID: String?) -> [String] {
        var result = globalTitles
        if let id = bundleID {
            result.append(contentsOf: perApp[id] ?? [])
        }
        return result
    }

    /// Returns true when `title` matches any pattern in `patterns`.
    /// Patterns without `*` or `?` are matched case- and diacritic-insensitively.
    /// Patterns containing `*` or `?` use glob semantics via NSPredicate LIKE[cd].
    nonisolated static func isIgnored(title: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if NSPredicate(format: "SELF LIKE[cd] %@", pattern).evaluate(with: title) {
                return true
            }
        }
        return false
    }

    func addGlobal(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !globalTitles.contains(trimmed) else { return }
        globalTitles.append(trimmed)
        save()
    }

    func removeGlobal(at offsets: IndexSet) {
        globalTitles.remove(atOffsets: offsets)
        save()
    }

    func addRule(bundleID: String, displayName: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appDisplayNames[bundleID] = displayName
        var titles = perApp[bundleID] ?? []
        guard !titles.contains(trimmed) else { return }
        titles.append(trimmed)
        perApp[bundleID] = titles
        save()
    }

    func removeRule(bundleID: String, at offsets: IndexSet) {
        var titles = perApp[bundleID] ?? []
        titles.remove(atOffsets: offsets)
        if titles.isEmpty {
            perApp.removeValue(forKey: bundleID)
            appDisplayNames.removeValue(forKey: bundleID)
        } else {
            perApp[bundleID] = titles
        }
        save()
    }

    func removeApp(_ bundleID: String) {
        perApp.removeValue(forKey: bundleID)
        appDisplayNames.removeValue(forKey: bundleID)
        save()
    }

    func isAppIgnored(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return ignoredApps[id] != nil
    }

    func addIgnoredApp(bundleID: String, displayName: String) {
        ignoredApps[bundleID] = displayName
        save()
    }

    func removeIgnoredApp(bundleID: String) {
        ignoredApps.removeValue(forKey: bundleID)
        save()
    }

    func addIgnoredMenu(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !ignoredMenuTitles.contains(trimmed) else { return }
        ignoredMenuTitles.append(trimmed)
        save()
    }

    func removeIgnoredMenu(at offsets: IndexSet) {
        ignoredMenuTitles.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        let data = IgnoreData(
            globalTitles: globalTitles,
            perApp: perApp,
            appDisplayNames: appDisplayNames,
            ignoredApps: ignoredApps,
            ignoredMenuTitles: ignoredMenuTitles
        )
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }
}

private struct IgnoreData: Codable {
    var globalTitles: [String]
    var perApp: [String: [String]]
    var appDisplayNames: [String: String]
    var ignoredApps: [String: String]
    var ignoredMenuTitles: [String]

    init(globalTitles: [String], perApp: [String: [String]],
         appDisplayNames: [String: String], ignoredApps: [String: String] = [:],
         ignoredMenuTitles: [String] = []) {
        self.globalTitles     = globalTitles
        self.perApp           = perApp
        self.appDisplayNames  = appDisplayNames
        self.ignoredApps      = ignoredApps
        self.ignoredMenuTitles = ignoredMenuTitles
    }

    // Custom decoder so that JSON written before `ignoredMenuTitles`/`ignoredApps`
    // were added decodes gracefully instead of throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        globalTitles      = try c.decode([String].self,            forKey: .globalTitles)
        perApp            = try c.decode([String: [String]].self,  forKey: .perApp)
        appDisplayNames   = try c.decode([String: String].self,    forKey: .appDisplayNames)
        ignoredApps       = try c.decodeIfPresent([String: String].self, forKey: .ignoredApps) ?? [:]
        ignoredMenuTitles = try c.decodeIfPresent([String].self,   forKey: .ignoredMenuTitles) ?? []
    }
}
