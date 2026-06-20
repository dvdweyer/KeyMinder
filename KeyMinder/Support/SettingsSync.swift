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
///   - Call `push()` whenever settings change (e.g. from a UserDefaults.didChangeNotification).
///   - Call `stop()` when the user disables sync.
@MainActor
final class SettingsSync {

    static let shared = SettingsSync()

    /// Keys written to and read from NSUbiquitousKeyValueStore.
    /// Excludes Mac-local keys: globalHotkey, didSetDefaultHotkey, doubleTapEnabled,
    /// doubleTapModifier, menuBarIconStyle, appIconVariant, matchAppIconToTrigger,
    /// launchAtLogin (SMAppService — not settable via UserDefaults at all).
    static let syncedKeys: [String] = [
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
    private var observer: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    private init() {}

    // MARK: Lifecycle

    func start() {
        pull()
        startObserving()
    }

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
        observer = nil
        defaultsObserver = nil
    }

    // MARK: Push / pull

    /// Writes all synced keys from UserDefaults → KVS.
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

    /// Writes all synced keys from KVS → UserDefaults.
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
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Only pull keys that actually changed.
            let changed = (notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            for key in changed where Self.syncedKeys.contains(key) {
                if let val = self.kvs.object(forKey: key) {
                    UserDefaults.standard.set(val, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            self.postChangeNotifications()
        }

        // Debounced push: whenever any UserDefaults key changes, push after a short delay.
        var debounceWork: DispatchWorkItem?
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            debounceWork?.cancel()
            let work = DispatchWorkItem { self?.push() }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    // MARK: Private helpers

    private func postChangeNotifications() {
        NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
        NotificationCenter.default.post(name: .receiveBetaUpdatesChanged, object: nil)
        NotificationCenter.default.post(name: .receiveAlphaUpdatesChanged, object: nil)
    }
}
