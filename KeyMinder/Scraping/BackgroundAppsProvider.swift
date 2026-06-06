import AppKit

/// Scrapes keyboard shortcuts from running menu-bar apps (activation policy
/// `.accessory`) other than KeyMinder itself and the current frontmost app.
///
/// Results are cached for `cacheTTL` seconds. The cache is keyed on the full
/// set of background apps; the frontmost-app exclusion is applied at read time
/// so switching frontmost apps never triggers a re-scrape.
enum BackgroundAppsProvider {

    // MARK: - Cache

    private struct CacheEntry {
        let pairs: [(bundleID: String, section: MenuSection)]
        let timestamp: Date
    }

    private static var cache: CacheEntry?
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 30

    // MARK: - Skip lists

    private static let skipIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.dock.extra",
        "com.apple.dock.external.extra.arm64",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.Siri",
        "com.apple.talagent",
        "com.apple.AirPlayUIAgent",
        "com.apple.wifi.WiFiAgent",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.loginwindow",
        "com.apple.wallpaper.agent",
        "com.apple.universalcontrol",
        "com.apple.WindowManager",
        "com.apple.coreservices.uiagent",
        "com.apple.security.Keychain-Circle-Notification",
        "com.apple.UserNotificationCenter",
        "com.apple.backgroundtaskmanagement.agent",
        "com.apple.AccessibilityUIServer",
        "com.apple.accessibility.AXVisualSupportAgent",
        "com.apple.AccessibilityVisualsAgent",
        "com.apple.SoftwareUpdateNotificationManager",
        "com.apple.systemevents",
        "com.apple.AppSSOAgent",
        "com.apple.CoreLocationAgent",
        "com.apple.AquaAppearanceHelper",
    ]

    private static let skipPrefixes: [String] = [
        "com.apple.WebKit",
    ]

    // MARK: - Public API

    /// Returns one `MenuSection` per background app that exposes keyboard
    /// shortcuts through the Accessibility API, sorted by app name.
    ///
    /// Results are served from cache when the cache is still warm. Only
    /// shortcuts likely to be global hotkeys are included (see `isAppOnly`).
    /// The ignore list is applied fresh on every call (not cached) so
    /// Settings changes take effect without a cache flush.
    ///
    /// - Parameters:
    ///   - excludingBundleID: bundle ID of the frontmost app; skipped so its
    ///     shortcuts aren't duplicated alongside the regular scrape.
    ///   - ignoredTitlesFor: closure that returns the set of lowercased titles
    ///     to suppress for a given app bundle ID; called on the main actor.
    @MainActor
    static func load(excluding excludingBundleID: String?,
                     ignoredTitlesFor: (String?) -> Set<String> = { _ in [] }) -> [MenuSection] {
        let pairs = cachedPairs()
        return pairs
            .filter { $0.bundleID != excludingBundleID }
            .compactMap { pair in
                applyIgnored(ignoredTitlesFor(pair.bundleID), to: pair.section)
            }
    }

    // MARK: - Cache management

    @MainActor
    private static func cachedPairs() -> [(bundleID: String, section: MenuSection)] {
        cacheLock.lock()
        let hit = cache
        cacheLock.unlock()

        if let hit, Date().timeIntervalSince(hit.timestamp) < cacheTTL {
            return hit.pairs
        }

        let fresh = scrapeAll()
        cacheLock.lock()
        cache = CacheEntry(pairs: fresh, timestamp: Date())
        cacheLock.unlock()
        return fresh
    }

    // MARK: - Scraping

    @MainActor
    private static func scrapeAll() -> [(bundleID: String, section: MenuSection)] {
        let ownID = Bundle.main.bundleIdentifier

        let candidates = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .accessory else { return false }
                guard let bid = app.bundleIdentifier else { return false }
                if bid == ownID { return false }
                if skipIDs.contains(bid) { return false }
                if skipPrefixes.contains(where: { bid.hasPrefix($0) }) { return false }
                return true
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        var result: [(bundleID: String, section: MenuSection)] = []
        for app in candidates {
            let name = app.localizedName ?? "App"
            let bundleID = app.bundleIdentifier ?? ""
            let rawSections = MenuScraper.scrape(pid: app.processIdentifier)
            let filtered = filterGlobalLikely(rawSections)
            let groups = filtered.flatMap(\.groups)
            guard !groups.isEmpty else { continue }
            result.append((bundleID, MenuSection(title: name, groups: groups)))
        }
        return result
    }

    // MARK: - Ignore list

    private static func applyIgnored(_ titles: Set<String>, to section: MenuSection) -> MenuSection? {
        guard !titles.isEmpty else { return section }
        let filteredGroups = section.groups.compactMap { group -> ShortcutGroup? in
            let kept = group.shortcuts.filter { !titles.contains($0.title.localizedLowercase) }
            return kept.isEmpty ? nil : ShortcutGroup(title: group.title, shortcuts: kept)
        }
        return filteredGroups.isEmpty ? nil : MenuSection(title: section.title, groups: filteredGroups)
    }

    // MARK: - Heuristic filter

    /// Removes shortcuts that are almost certainly in-app-only rather than
    /// globally registered. Specifically: shortcuts whose only modifier is ⌘.
    ///
    /// Background apps very rarely register single-⌘ combos as global hotkeys;
    /// those are standard app commands (⌘Q, ⌘H, ⌘W, ⌘,, …) that only fire
    /// for the frontmost app. Global hotkeys from menu-bar apps almost always
    /// include at least one of ⌃ or ⌥ alongside ⌘, or use ⌃/⌥ alone.
    private static func filterGlobalLikely(_ sections: [MenuSection]) -> [MenuSection] {
        sections.compactMap { section in
            let filteredGroups = section.groups.compactMap { group -> ShortcutGroup? in
                let kept = group.shortcuts.filter { !isAppOnly($0) }
                return kept.isEmpty ? nil : ShortcutGroup(title: group.title, shortcuts: kept)
            }
            return filteredGroups.isEmpty ? nil : MenuSection(title: section.title, groups: filteredGroups)
        }
    }

    private static func isAppOnly(_ shortcut: Shortcut) -> Bool {
        shortcut.modifiers.count == 1 && shortcut.modifiers.contains("⌘")
    }
}
