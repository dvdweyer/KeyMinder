import Foundation

/// Reads macOS system-wide shortcuts from `com.apple.symbolichotkeys.plist`
/// and returns them as a `MenuSection` ready to append to the popup.
enum SystemShortcutsProvider {

    // MARK: - Public API

    /// Loads and formats enabled system shortcuts.  Returns `nil` when the
    /// plist is missing, unreadable, or produces no displayable shortcuts.
    static func load() -> MenuSection? {
        let plistURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")

        guard let data = try? Data(contentsOf: plistURL),
              let top = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                  as? [String: Any],
              let hotkeys = top["AppleSymbolicHotKeys"] as? [String: Any]
        else { return nil }

        // Build a set of explicitly-disabled action IDs so we can skip defaults.
        var disabledIDs: Set<Int> = []
        for (key, rawEntry) in hotkeys {
            guard let id = Int(key),
                  let entry = rawEntry as? [String: Any],
                  let enabled = entry["enabled"] as? Bool, !enabled
            else { continue }
            disabledIDs.insert(id)
        }

        // Collect (actionID → keys string) for every enabled entry with parameters.
        var resolved: [Int: String] = [:]

        // 1. Bundled defaults for IDs that macOS may not write unless overridden.
        for (id, params) in Self.bundledDefaults {
            guard !disabledIDs.contains(id) else { continue }
            if let keys = formatParameters(params) {
                resolved[id] = keys
            }
        }

        // 2. Plist entries override or add to the bundled defaults.
        for (key, rawEntry) in hotkeys {
            guard let id = Int(key),
                  let entry = rawEntry as? [String: Any],
                  let enabled = entry["enabled"] as? Bool, enabled,
                  let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [Any],
                  params.count >= 3,
                  let keyChar = params[0] as? Int,
                  let virtualKey = params[1] as? Int,
                  let flags = params[2] as? Int,
                  let keys = formatParameters([keyChar, virtualKey, flags])
            else { continue }
            resolved[id] = keys
        }

        guard !resolved.isEmpty else { return nil }

        // Build named ShortcutGroups in display order.
        var groups: [ShortcutGroup] = [ShortcutGroup(title: nil, shortcuts: [])]
        for (groupName, ids) in Self.groupOrder {
            let shortcuts = ids.compactMap { id -> Shortcut? in
                guard let keys = resolved[id],
                      let name = Self.actionNames[id] else { return nil }
                return Shortcut(title: name, keys: keys)
            }
            guard !shortcuts.isEmpty else { continue }
            groups.append(ShortcutGroup(title: groupName, shortcuts: shortcuts))
        }

        guard groups.count > 1 else { return nil }
        return MenuSection(title: "System", groups: groups)
    }

    // MARK: - Formatter

    /// Converts a `[keyChar, virtualKey, nsFlags]` triple into a display string.
    private static func formatParameters(_ params: [Int]) -> String? {
        guard params.count >= 3 else { return nil }
        let (keyChar, virtualKey, nsFlags) = (params[0], params[1], params[2])

        let cmdChar: String?
        if keyChar >= 0x20 && keyChar <= 0x7E {
            cmdChar = String(UnicodeScalar(keyChar)!)
        } else {
            cmdChar = nil
        }

        return ShortcutFormatter.format(
            cmdChar: cmdChar,
            virtualKey: virtualKey,
            glyph: nil,
            modifiers: axModifiers(from: nsFlags)
        )
    }

    /// Converts NSEvent modifier flags to the AX modifier bit format that
    /// `ShortcutFormatter` expects (shift=1, option=2, control=4, no-cmd=8).
    private static func axModifiers(from nsFlags: Int) -> Int {
        var ax = 0
        if nsFlags & 0x20000  != 0 { ax |= 1 }   // shift
        if nsFlags & 0x80000  != 0 { ax |= 2 }   // option
        if nsFlags & 0x40000  != 0 { ax |= 4 }   // control
        if nsFlags & 0x100000 == 0 { ax |= 8 }   // no-command
        return ax
    }

    // MARK: - Static tables

    /// Default [keyChar, virtualKey, nsFlags] for well-known IDs that macOS
    /// doesn't write to the plist unless the user customises them.
    private static let bundledDefaults: [Int: [Int]] = [
        7: [32, 49, 0x100000],          // ⌘Space  — Spotlight Search
        8: [32, 49, 0x180000],          // ⌥⌘Space — Finder Search Window
    ]

    /// Display name for each action ID.
    private static let actionNames: [Int: String] = [
        // Spotlight
        7:   "Show Spotlight Search",
        8:   "Show Finder Search Window",
        // Screenshots
        23:  "Save Screenshot of Entire Screen",
        24:  "Copy Screenshot of Entire Screen",
        25:  "Save Screenshot of Selected Area",
        26:  "Copy Screenshot of Selected Area",
        27:  "Screenshot and Recording Options",
        28:  "Record Entire Screen",
        29:  "Record Selected Area",
        30:  "Copy Recording of Entire Screen",
        31:  "Copy Recording of Selected Area",
        184: "Screenshot and Recording Options",
        // Mission Control
        32:  "Mission Control",
        33:  "Application Windows",
        34:  "Show Desktop",
        36:  "Move Left a Space",
        37:  "Move Right a Space",
        51:  "Switch to Desktop 1",
        52:  "Switch to Desktop 2",
        53:  "Switch to Desktop 3",
        54:  "Switch to Desktop 4",
        55:  "Switch to Desktop 5",
        56:  "Switch to Desktop 6",
        57:  "Switch to Desktop 7",
        58:  "Switch to Desktop 8",
        79:  "Switch to Desktop 1",
        80:  "Switch to Desktop 2",
        81:  "Switch to Desktop 3",
        82:  "Switch to Desktop 4",
        // Keyboard Navigation
        13:  "Move Focus to Menu Bar",
        14:  "Move Focus to Dock",
        15:  "Move Focus to Active Window",
        16:  "Move Focus to Toolbar",
        17:  "Move Focus to Floating Window",
        18:  "Move Focus to Next Window",
        19:  "Move Focus to Window Drawer",
        20:  "Move Focus to Status Menus",
        // Siri
        160: "Show Siri",
        164: "Turn VoiceOver On/Off",
    ]

    /// Groups in display order; each entry lists the action IDs in that group.
    private static let groupOrder: [(String, [Int])] = [
        ("Spotlight",            [7, 8]),
        ("Screenshots",          [23, 24, 25, 26, 27, 28, 29, 30, 31, 184]),
        ("Mission Control",      [32, 33, 34, 36, 37, 51, 52, 53, 54, 55, 56, 57, 58, 79, 80, 81, 82]),
        ("Keyboard Navigation",  [13, 14, 15, 16, 17, 18, 19, 20]),
        ("Siri & Accessibility", [160, 164]),
    ]
}
