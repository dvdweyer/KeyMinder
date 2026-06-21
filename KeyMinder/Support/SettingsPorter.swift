import Foundation

enum SettingsPorter {

    static let keys: [String] = [
        // Hotkey
        "globalHotkey", "didSetDefaultHotkey",
        // Appearance
        "keyAccentColor",
        // Double-tap trigger
        "doubleTapEnabled", "doubleTapModifier",
        "menuBarIconStyle", "appIconVariant", "matchAppIconToTrigger",
        // Popup content
        "showAllMenuItems", "requireFilterForAllMenuItems", "hideLargeSubmenus",
        "showSystemShortcuts", "showDeactivatedSystemShortcuts",
        "showThirdPartyShortcuts", "wrapLongSections",
        "alwaysShowFavourites", "showConflictIndicator",
        // Updates
        "SUEnableAutomaticChecks", "receiveBetaUpdates", "receiveAlphaUpdates",
        // Ignore list
        "ignoreList", "ignoreListEnabled", "ignoreListShowWhenFiltering",
        // Favorites
        "pinnedShortcuts",
        // Developer
        "debugLoggingEnabled",
    ]

    static func export() throws -> Data {
        var dict: [String: Any] = [
            "__version": 1,
            "__exportedAt": ISO8601DateFormatter().string(from: Date()),
            "__keyminderVersion": Bundle.main
                .infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ]
        for key in keys {
            if let val = UserDefaults.standard.object(forKey: key) {
                dict[key] = val
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    static func apply(_ data: Data) throws {
        guard let dict = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for key in keys {
            if let val = dict[key] { UserDefaults.standard.set(val, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}
