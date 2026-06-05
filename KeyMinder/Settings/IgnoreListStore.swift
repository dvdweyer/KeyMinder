import Foundation
import SwiftUI

@Observable @MainActor
final class IgnoreListStore {
    static let shared = IgnoreListStore()

    private static let defaultsKey = "ignoreList"
    private static let didSeedKey  = "didSeedIgnoreList"

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
            globalTitles    = stored.globalTitles
            perApp          = stored.perApp
            appDisplayNames = stored.appDisplayNames
            ignoredApps     = stored.ignoredApps
        } else {
            globalTitles    = []
            perApp          = [:]
            appDisplayNames = [:]
            ignoredApps     = [:]
        }

        if !UserDefaults.standard.bool(forKey: Self.didSeedKey) {
            globalTitles = ["Minimize", "Fill", "Centre", "Move & Resize"]
            UserDefaults.standard.set(true, forKey: Self.didSeedKey)
            save()
        }
    }

    /// Returns the lowercased set of titles to suppress for a given app.
    /// Includes global titles plus any app-specific ones.
    func ignoredTitles(for bundleID: String?) -> Set<String> {
        var result = Set(globalTitles.map { $0.localizedLowercase })
        if let id = bundleID {
            (perApp[id] ?? []).forEach { result.insert($0.localizedLowercase) }
        }
        return result
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

    private func save() {
        let data = IgnoreData(
            globalTitles: globalTitles,
            perApp: perApp,
            appDisplayNames: appDisplayNames,
            ignoredApps: ignoredApps
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

    init(globalTitles: [String], perApp: [String: [String]],
         appDisplayNames: [String: String], ignoredApps: [String: String] = [:]) {
        self.globalTitles    = globalTitles
        self.perApp          = perApp
        self.appDisplayNames = appDisplayNames
        self.ignoredApps     = ignoredApps
    }
}
