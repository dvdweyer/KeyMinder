import Foundation

// MARK: - UserDefaults key

extension UserDefaults {
    private static let iCloudSyncEnabledKey = "iCloudSyncEnabled"

    var iCloudSyncEnabled: Bool {
        get { bool(forKey: Self.iCloudSyncEnabledKey) }
        set { set(newValue, forKey: Self.iCloudSyncEnabledKey) }
    }
}

// MARK: - SettingsSync

/// Syncs a curated subset of UserDefaults to iCloud Key-Value Store so settings
/// are shared across the user's Macs. Mac-specific settings (global hotkey,
/// double-tap trigger, icon style) are intentionally excluded.
///
/// Usage:
///   - Call `start()` on app launch when `iCloudSyncEnabled` is true.
///   - Call `push()` whenever settings should be written out immediately.
///   - Call `stop()` when the user disables sync.
@MainActor
final class SettingsSync {

    static let shared = SettingsSync()

    /// Keys written to and read from NSUbiquitousKeyValueStore.
    /// Excludes Mac-local keys: globalHotkey, didSetDefaultHotkey, doubleTapEnabled,
    /// doubleTapModifier, menuBarIconStyle, appIconVariant, matchAppIconToTrigger,
    /// and launchAtLogin (SMAppService — not a UserDefaults key at all).
    nonisolated static let syncedKeys: [String] = [
        "pinnedShortcuts",
        "ignoreList", "ignoreListEnabled", "ignoreListShowWhenFiltering",
        "keyAccentColor",
        "showAllMenuItems", "requireFilterForAllMenuItems", "hideLargeSubmenus",
        "showSystemShortcuts", "showDeactivatedSystemShortcuts",
        "showThirdPartyShortcuts", "wrapLongSections",
        "alwaysShowFavourites", "showConflictIndicator",
        "SUEnableAutomaticChecks", "receiveBetaUpdates", "receiveAlphaUpdates",
        "debugLoggingEnabled",
    ]

    private var kvs: NSUbiquitousKeyValueStore { .default }
    private var kvsObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: Lifecycle

    func start() {
        pull()
        startObserving()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let o = kvsObserver { NotificationCenter.default.removeObserver(o) }
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
        kvsObserver = nil
        defaultsObserver = nil
    }

    // MARK: Push / pull

    /// Writes all synced keys from UserDefaults → KVS and flushes.
    func push() {
        for key in Self.syncedKeys {
            if let val = UserDefaults.standard.object(forKey: key) {
                kvs.set(val, forKey: key)
            } else {
                kvs.removeObject(forKey: key)
            }
        }
        kvs.synchronize()
    }

    /// Reads all synced keys from KVS → UserDefaults.
    private func pull() {
        for key in Self.syncedKeys {
            if let val = kvs.object(forKey: key) {
                UserDefaults.standard.set(val, forKey: key)
            }
        }
        postChangeNotifications()
    }

    // MARK: Observing

    private func startObserving() {
        // KVS change from another device → pull the changed keys.
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                let changed = (notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                    as? [String]) ?? []
                for key in changed where SettingsSync.syncedKeys.contains(key) {
                    if let val = self.kvs.object(forKey: key) {
                        UserDefaults.standard.set(val, forKey: key)
                    } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
                self.postChangeNotifications()
            }
        }

        // Local settings change → debounced push to KVS.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebounce() }
        }
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            push()
        }
    }

    // MARK: Helpers

    private func postChangeNotifications() {
        NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
        NotificationCenter.default.post(name: .receiveBetaUpdatesChanged, object: nil)
        NotificationCenter.default.post(name: .receiveAlphaUpdatesChanged, object: nil)
    }
}
