import Foundation
import os

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
        Logger.settings.log("SettingsSync.start() snapshot keys=\(self.snapshot.count, privacy: .public) didInit=\(UserDefaults.standard.bool(forKey: Self.didInitKey), privacy: .public)")
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

    /// Starts sync with local settings winning: stamps all local values with the
    /// current time and pushes them to KVS before pulling, so remote values with
    /// older timestamps are not applied. Used when the user explicitly chooses to
    /// keep local settings during first-enable conflict resolution.
    func startWithLocalPriority() {
        snapshot = currentSyncedValues()
        let now = Date().timeIntervalSince1970
        var lts = localTimestamps()
        for key in Self.syncedKeys {
            // Stamp every synced key with `now`, including keys with no local value —
            // "locally absent" is a meaningful state here (e.g. accent colour following
            // system default), and leaving its timestamp at 0 would let the
            // applyRemoteIfNewer() call below adopt a remote value, partially ignoring
            // the user's "keep local" choice. Deletions are still never propagated: a
            // locally-absent key's remote value in KVS is left untouched, not removed.
            lts[key] = now
            guard let val = UserDefaults.standard.object(forKey: key) as? NSObject else { continue }
            kvs.set(val, forKey: key)
            kvs.set(now, forKey: Self.tsKey(key))
            snapshot[key] = val
        }
        setLocalTimestamps(lts)
        kvs.synchronize()
        UserDefaults.standard.set(true, forKey: Self.didInitKey)
        applyRemoteIfNewer()
        startObserving()
    }

    /// Returns true if enabling sync right now would pull any remote values that are
    /// newer than local ones — i.e., remote settings would overwrite local. Pure check,
    /// no side effects. Call before `start()` to decide whether to prompt the user.
    func wouldApplyRemote() -> Bool {
        let lts = localTimestamps()
        for key in Self.syncedKeys {
            guard kvs.object(forKey: key) != nil else { continue }
            let kvsTs = kvs.double(forKey: Self.tsKey(key))
            let localTs = lts[key] ?? 0
            if Self.shouldApplyRemote(kvsTs: kvsTs, localTs: localTs) { return true }
        }
        return false
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let o = kvsObserver { NotificationCenter.default.removeObserver(o) }
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
        kvsObserver = nil
        defaultsObserver = nil
    }

    /// Wipes all KeyMinder entries from iCloud Key-Value Store and resets local
    /// sync metadata. Does NOT touch local UserDefaults settings — only clears
    /// the iCloud copy. Resets didInitSyncV2 so the next start() treats this
    /// Mac as a fresh install and re-seeds KVS from local values via additivePublish.
    func clearICloudData() {
        Logger.settings.log("SettingsSync.clearICloudData() wiping \(Self.syncedKeys.count, privacy: .public) KVS keys")
        stop()
        for key in Self.syncedKeys {
            kvs.removeObject(forKey: key)
            kvs.removeObject(forKey: Self.tsKey(key))
        }
        kvs.synchronize()
        UserDefaults.standard.removeObject(forKey: Self.localTimestampsKey)
        UserDefaults.standard.removeObject(forKey: Self.didInitKey)
        snapshot = [:]
    }

    // MARK: Push (local → KVS)

    /// Pushes only the synced keys whose value actually changed since the last sync.
    /// Unrelated UserDefaults churn (non-synced keys) resolves to an empty changed set
    /// and writes nothing. Per key, we only overwrite KVS when our timestamp is at least
    /// as new as the remote's — otherwise we adopt the newer remote value instead of
    /// clobbering it.
    private func push() {
        let current = currentSyncedValues()
        let changed = Self.changedKeys(current: current, snapshot: snapshot)
        guard !changed.isEmpty else { return }

        var lts = localTimestamps()
        let now = Date().timeIntervalSince1970

        for key in changed {
            guard let curVal = current[key] else {
                // Key removed locally (e.g. accent reset to system). Only clear it from
                // KVS when our deletion is at least as new as the remote value — otherwise
                // a genuinely newer remote edit would be destroyed without ever being
                // consulted. Never propagate our deletion as a tombstone to other Macs.
                // Compare against a fresh `now` (the deletion is happening now), not
                // `lts[key]` (the last time this key was *synced*, which can be stale if
                // a remote edit landed after our last sync but before this deletion) —
                // mirrors the non-deletion branch's `now >= kvsTs` check below.
                let kvsTs = kvs.double(forKey: Self.tsKey(key))
                if now >= kvsTs {
                    kvs.removeObject(forKey: key)
                    kvs.removeObject(forKey: Self.tsKey(key))
                    lts.removeValue(forKey: key)
                    snapshot.removeValue(forKey: key)
                } else if let remoteVal = kvs.object(forKey: key) as? NSObject {
                    Logger.settings.log("SettingsSync.push: remote '\(key, privacy: .public)' is newer than local deletion (remote ts=\(kvsTs, privacy: .public) > local ts=\(now, privacy: .public)); adopting remote value instead")
                    applyToLocal(remoteVal, forKey: key)
                    lts[key] = kvsTs
                    snapshot[key] = remoteVal
                }
                continue
            }
            let kvsTs = kvs.double(forKey: Self.tsKey(key))
            let remoteVal = kvs.object(forKey: key) as? NSObject
            if now >= kvsTs || remoteVal == nil {
                Logger.settings.log("SettingsSync.push: pushing '\(key, privacy: .public)' to KVS (local ts=\(now, privacy: .public) >= remote ts=\(kvsTs, privacy: .public) or no remote value)")
                kvs.set(curVal, forKey: key)
                kvs.set(now, forKey: Self.tsKey(key))
                lts[key] = now
                snapshot[key] = curVal
            } else {
                // Remote is strictly newer — adopt it rather than overwrite with our older edit.
                Logger.settings.log("SettingsSync.push: adopting remote value for '\(key, privacy: .public)' (remote ts=\(kvsTs, privacy: .public) > local ts=\(now, privacy: .public))")
                applyToLocal(remoteVal!, forKey: key)
                lts[key] = kvsTs
                snapshot[key] = remoteVal
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
            Logger.settings.log("SettingsSync.applyRemoteIfNewer: applying remote '\(key, privacy: .public)' (remote ts=\(kvsTs, privacy: .public) > local ts=\(localTs, privacy: .public))")
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
        NotificationCenter.default.post(name: .receiveBetaUpdatesChanged, object: nil)
        NotificationCenter.default.post(name: .receiveAlphaUpdatesChanged, object: nil)
    }
}
