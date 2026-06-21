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
/// Conflict model: **per-key last-writer-wins by timestamp.** Each synced key `K`
/// carries a sibling `"__ts_<K>"` timestamp in KVS and a mirror in the local
/// `"__localSyncTimestamps"` dictionary. A remote value is only applied when its
/// timestamp is strictly newer than the local one, so editing different settings on
/// different Macs never clobbers, and an upgrade never overwrites local settings with
/// unprovenanced (timestamp-0) remote data. Wall-clock `Date()` is used for stamps —
/// KVS offers no server-assigned version, so gross clock skew between Macs is the one
/// residual way a same-key conflict can resolve "wrong"; the per-key conditional write
/// keeps that to genuine same-key, same-window edits only.
///
/// Usage:
///   - Call `start()` on app launch when `iCloudSyncEnabled` is true.
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

    private static let localTimestampsKey = "__localSyncTimestamps"
    private static let didInitKey         = "didInitSyncV2"
    nonisolated private static func tsKey(_ key: String) -> String { "__ts_\(key)" }

    private var kvs: NSUbiquitousKeyValueStore { .default }
    private var kvsObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    /// Last-known synced values, used to detect which keys a local change touched.
    /// Updated on every push and every applied remote change, so writes SettingsSync
    /// makes itself never register as user edits (no echo push).
    private var snapshot: [String: NSObject] = [:]

    private init() {}

    // MARK: Lifecycle

    func start() {
        snapshot = currentSyncedValues()
        // One-time non-destructive publish: seed KVS keys that don't exist yet from
        // local values. Never overwrites an existing KVS value, so a sparse Mac can't
        // wipe a richer one. Replaces the old (dangerous) full migration push.
        if !UserDefaults.standard.bool(forKey: Self.didInitKey) {
            additivePublish()
            UserDefaults.standard.set(true, forKey: Self.didInitKey)
        }
        applyRemoteIfNewer()   // launch pull
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

    // MARK: Push (local → KVS)

    /// Pushes only the synced keys whose value actually changed since the last sync.
    /// Unrelated UserDefaults churn (non-synced keys) resolves to an empty changed set
    /// and writes nothing. Per key, we only overwrite KVS when our timestamp is at least
    /// as new as the remote's — otherwise we adopt the newer remote value instead of
    /// clobbering it.
    private func push() {
        var current = currentSyncedValues()
        let changed = Self.changedKeys(current: current, snapshot: snapshot)
        guard !changed.isEmpty else { return }

        var lts = localTimestamps()
        let now = Date().timeIntervalSince1970

        for key in changed {
            guard let curVal = current[key] else {
                // Key removed locally (e.g. accent reset to system). Clear it from KVS so
                // no stale value is served; do not propagate as a deletion to other Macs.
                kvs.removeObject(forKey: key)
                kvs.removeObject(forKey: Self.tsKey(key))
                lts.removeValue(forKey: key)
                snapshot.removeValue(forKey: key)
                continue
            }
            let kvsTs = kvs.double(forKey: Self.tsKey(key))
            let remoteVal = kvs.object(forKey: key) as? NSObject
            if now >= kvsTs || remoteVal == nil {
                kvs.set(curVal, forKey: key)
                kvs.set(now, forKey: Self.tsKey(key))
                lts[key] = now
                snapshot[key] = curVal
            } else {
                // Remote is strictly newer — adopt it rather than overwrite with our older edit.
                applyToLocal(remoteVal!, forKey: key)
                lts[key] = kvsTs
                snapshot[key] = remoteVal
                current[key] = remoteVal
            }
        }

        setLocalTimestamps(lts)
        kvs.synchronize()
    }

    /// Seeds KVS with local values for synced keys that have no KVS value yet.
    private func additivePublish() {
        let lts = localTimestamps()
        for key in Self.syncedKeys {
            guard kvs.object(forKey: key) == nil,
                  let val = UserDefaults.standard.object(forKey: key) as? NSObject else { continue }
            kvs.set(val, forKey: key)
            kvs.set(lts[key] ?? 0, forKey: Self.tsKey(key))
        }
        kvs.synchronize()
    }

    // MARK: Pull (KVS → local)

    /// Applies every synced KVS key whose timestamp is newer than the local one.
    /// Shared by the launch pull and the live external-change handler so both behave
    /// identically. Keys absent from KVS are left untouched locally (no deletion
    /// propagation). Reads the KVS `changed` list is unnecessary — we re-evaluate all.
    private func applyRemoteIfNewer() {
        var lts = localTimestamps()
        var changedAny = false

        for key in Self.syncedKeys {
            guard let remoteVal = kvs.object(forKey: key) as? NSObject else { continue }
            let kvsTs = kvs.double(forKey: Self.tsKey(key))
            let localTs = lts[key] ?? 0
            guard Self.shouldApplyRemote(kvsTs: kvsTs, localTs: localTs) else { continue }
            applyToLocal(remoteVal, forKey: key)
            lts[key] = kvsTs
            snapshot[key] = remoteVal
            changedAny = true
        }

        if changedAny {
            setLocalTimestamps(lts)
            postChangeNotifications()
        }
    }

    // MARK: Observing

    private func startObserving() {
        kvsObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyRemoteIfNewer() }
        }

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

    // MARK: Pure resolution helpers (testable)

    /// Synced keys whose value differs between `current` and `snapshot`. A key present in
    /// one but absent in the other counts as changed (covers additions and removals).
    nonisolated static func changedKeys(current: [String: NSObject],
                                        snapshot: [String: NSObject]) -> [String] {
        var keys = Set(current.keys)
        keys.formUnion(snapshot.keys)
        return keys.filter { !valuesEqual(current[$0], snapshot[$0]) }
    }

    nonisolated static func valuesEqual(_ a: NSObject?, _ b: NSObject?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.isEqual(y)
        default: return false
        }
    }

    /// A remote value should overwrite local only when its provenance is strictly newer.
    /// Equal or unknown (0) timestamps keep the local value — the non-destructive default.
    nonisolated static func shouldApplyRemote(kvsTs: Double, localTs: Double) -> Bool {
        kvsTs > localTs
    }

    // MARK: Helpers

    private func currentSyncedValues() -> [String: NSObject] {
        var result: [String: NSObject] = [:]
        for key in Self.syncedKeys {
            if let val = UserDefaults.standard.object(forKey: key) as? NSObject {
                result[key] = val
            }
        }
        return result
    }

    private func applyToLocal(_ value: NSObject, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func localTimestamps() -> [String: Double] {
        (UserDefaults.standard.dictionary(forKey: Self.localTimestampsKey) as? [String: Double]) ?? [:]
    }

    private func setLocalTimestamps(_ ts: [String: Double]) {
        UserDefaults.standard.set(ts, forKey: Self.localTimestampsKey)
    }

    private func postChangeNotifications() {
        FavouritesStore.shared.reload()
        IgnoreListStore.shared.reload()
        ThemeSettings.shared.reload()
        NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
        NotificationCenter.default.post(name: .receiveBetaUpdatesChanged, object: nil)
        NotificationCenter.default.post(name: .receiveAlphaUpdatesChanged, object: nil)
    }
}
