import Foundation

/// Reads macOS system-wide shortcuts from `com.apple.symbolichotkeys.plist`
/// and returns them as a `MenuSection` ready to append to the popup.
enum SystemShortcutsProvider {

    // MARK: - Public API

    /// Loads system shortcuts and user-defined application shortcuts.
    /// Returns `nil` when the plist is missing or produces no displayable shortcuts.
    static func load() -> MenuSection? {
        let plistURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")

        guard let data = try? Data(contentsOf: plistURL),
              let top = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                  as? [String: Any],
              let hotkeys = top["AppleSymbolicHotKeys"] as? [String: Any]
        else {
            // Plist unreadable: fall back to all bundled defaults.
            return buildSection(resolved: allEnabledDefaults())
        }

        var resolved: [Int: (keys: String, isDisabled: Bool)] = [:]

        // 1. Seed from bundled defaults — enabled items at their macOS-default state.
        for (id, params) in Self.enabledByDefault {
            if let keys = formatParameters(params) { resolved[id] = (keys, false) }
        }
        // Seed disabled-by-default items.
        for (id, params) in Self.disabledByDefault {
            if let keys = formatParameters(params) { resolved[id] = (keys, true) }
        }

        // 2. Apply plist overrides.
        for (key, rawEntry) in hotkeys {
            guard let id = Int(key),
                  let entry = rawEntry as? [String: Any],
                  let enabled = entry["enabled"] as? Bool
            else { continue }

            let plParams: [Int]? = {
                guard let value = entry["value"] as? [String: Any],
                      let p = value["parameters"] as? [Any],
                      p.count >= 3,
                      let k0 = p[0] as? Int, let k1 = p[1] as? Int, let k2 = p[2] as? Int
                else { return nil }
                // Treat obviously-invalid sentinel values (65535 for ALL three) as absent.
                return (k0 == 65535 && k1 == 65535) ? nil : [k0, k1, k2]
            }()

            if enabled {
                // Plist enabled: override with plist params when present.
                if let p = plParams, let keys = formatParameters(p) {
                    resolved[id] = (keys, false)
                }
                // If no valid plist params, keep existing bundled default (already seeded).
            } else {
                // Plist disabled: prefer plist params; fall back to bundled default params.
                let params = plParams
                    ?? Self.enabledByDefault[id]
                    ?? Self.disabledByDefault[id]
                if let params, let keys = formatParameters(params) {
                    resolved[id] = (keys, true)
                }
            }
        }

        return buildSection(resolved: resolved)
    }

    // MARK: - Section builder

    private static func buildSection(resolved: [Int: (keys: String, isDisabled: Bool)]) -> MenuSection? {
        var groups: [ShortcutGroup] = [ShortcutGroup(title: nil, shortcuts: [])]

        for (groupName, ids) in Self.groupOrder {
            let shortcuts = ids.compactMap { id -> Shortcut? in
                guard let (keys, isDisabled) = resolved[id],
                      let name = Self.actionNames[id] else { return nil }
                return Shortcut(title: name, keys: keys, isDisabled: isDisabled)
            }
            guard !shortcuts.isEmpty else { continue }
            groups.append(ShortcutGroup(title: groupName, shortcuts: shortcuts))
        }

        if let appGroup = loadAppShortcuts() {
            groups.append(appGroup)
        }

        guard groups.count > 1 else { return nil }
        return MenuSection(title: "System", groups: groups)
    }

    /// Fallback: all bundled defaults in their default enabled/disabled state, no plist overrides.
    private static func allEnabledDefaults() -> [Int: (keys: String, isDisabled: Bool)] {
        var result: [Int: (keys: String, isDisabled: Bool)] = [:]
        for (id, params) in enabledByDefault {
            if let keys = formatParameters(params) { result[id] = (keys, false) }
        }
        for (id, params) in disabledByDefault {
            if let keys = formatParameters(params) { result[id] = (keys, true) }
        }
        return result
    }

    // MARK: - Application shortcuts (NSUserKeyEquivalents)

    /// Reads `NSUserKeyEquivalents` from `~/.GlobalPreferences.plist` and returns
    /// a `ShortcutGroup` for "All Applications" shortcuts, or `nil` if none exist.
    private static func loadAppShortcuts() -> ShortcutGroup? {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/.GlobalPreferences.plist")

        guard let data = try? Data(contentsOf: url),
              let top = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                  as? [String: Any],
              let equivs = top["NSUserKeyEquivalents"] as? [String: String],
              !equivs.isEmpty
        else { return nil }

        let shortcuts = equivs.compactMap { title, value -> Shortcut? in
            guard let keys = formatUserKeyEquivalent(value) else { return nil }
            return Shortcut(title: title, keys: keys)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return shortcuts.isEmpty ? nil : ShortcutGroup(title: "All Applications", shortcuts: shortcuts)
    }

    /// Converts an `NSUserKeyEquivalents` value string (e.g. `"@$/"`) into a
    /// display string (e.g. `"⇧⌘/"`). Returns `nil` for empty or unparseable strings.
    private static func formatUserKeyEquivalent(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        var ctrl = false, opt = false, shift = false, cmd = false
        var remaining = value[...]

        // Consume modifier prefix characters; stop at the first non-modifier.
        while let ch = remaining.first, "^~$@".contains(ch) {
            switch ch {
            case "^": ctrl  = true
            case "~": opt   = true
            case "$": shift = true
            default:  cmd   = true  // "@"
            }
            remaining = remaining.dropFirst()
        }

        guard let keyCh = remaining.first else { return nil }
        let keyDisplay: String
        switch keyCh {
        case "\t":       keyDisplay = "⇥"
        case "\r", "\n": keyDisplay = "↩"
        case "\u{1b}":   keyDisplay = "⎋"
        case "\u{08}", "\u{7f}": keyDisplay = "⌫"
        case " ":        keyDisplay = "Space"
        case "\u{f700}": keyDisplay = "↑"
        case "\u{f701}": keyDisplay = "↓"
        case "\u{f702}": keyDisplay = "←"
        case "\u{f703}": keyDisplay = "→"
        case "\u{f728}": keyDisplay = "⌦"
        case "\u{f704}": keyDisplay = "F1"
        case "\u{f705}": keyDisplay = "F2"
        case "\u{f706}": keyDisplay = "F3"
        case "\u{f707}": keyDisplay = "F4"
        case "\u{f708}": keyDisplay = "F5"
        case "\u{f709}": keyDisplay = "F6"
        case "\u{f70a}": keyDisplay = "F7"
        case "\u{f70b}": keyDisplay = "F8"
        case "\u{f70c}": keyDisplay = "F9"
        case "\u{f70d}": keyDisplay = "F10"
        case "\u{f70e}": keyDisplay = "F11"
        case "\u{f70f}": keyDisplay = "F12"
        default:         keyDisplay = String(keyCh).uppercased()
        }

        var result = ""
        if ctrl  { result += "⌃" }
        if opt   { result += "⌥" }
        if shift { result += "⇧" }
        if cmd   { result += "⌘" }
        result += keyDisplay
        return result
    }

    // MARK: - Parameter formatter

    /// Converts a `[keyChar, virtualKey, nsFlags]` triple into a display string.
    private static func formatParameters(_ params: [Int]) -> String? {
        guard params.count >= 3 else { return nil }
        let (keyChar, virtualKey, nsFlags) = (params[0], params[1], params[2])
        let cmdChar: String? = (keyChar >= 0x20 && keyChar <= 0x7E)
            ? String(UnicodeScalar(keyChar)!) : nil
        return ShortcutFormatter.format(
            cmdChar: cmdChar,
            virtualKey: virtualKey,
            glyph: nil,
            modifiers: axModifiers(from: nsFlags)
        )
    }

    /// Converts NSEvent modifier flags to the AX modifier bit format used by
    /// `ShortcutFormatter` (shift=1, option=2, control=4, no-cmd=8).
    private static func axModifiers(from nsFlags: Int) -> Int {
        var ax = 0
        if nsFlags & 0x20000  != 0 { ax |= 1 }   // shift
        if nsFlags & 0x80000  != 0 { ax |= 2 }   // option
        if nsFlags & 0x40000  != 0 { ax |= 4 }   // control
        if nsFlags & 0x100000 == 0 { ax |= 8 }   // no-command
        return ax
    }

    // MARK: - Bundled defaults

    /// Shortcut parameters `[keyChar, virtualKey, nsFlags]` for IDs that are
    /// **enabled** in a default macOS installation. Not present in the plist
    /// unless the user overrides or disables them.
    private static let enabledByDefault: [Int: [Int]] = [
        // Spotlight
        64: [32, 49, 1048576],      // ⌘Space
        65: [32, 49, 1572864],      // ⌥⌘Space
        // Screenshots — on by default; plist entry means user disabled them
        28: [51, 20, 1179648],      // ⇧⌘3
        29: [51, 20, 1441792],      // ⌃⇧⌘3
        30: [52, 21, 1179648],      // ⇧⌘4
        31: [52, 21, 1441792],      // ⌃⇧⌘4
        184: [53, 23, 1179648],     // ⇧⌘5
        // Mission Control
        32: [65535, 126, 262144],   // ⌃↑
        33: [65535, 125, 262144],   // ⌃↓
        36: [65535, 103, 0],        // F11 (Show Desktop)
        // Keyboard navigation (⌃F2–F8, ⌘`)
        7:  [65535, 120, 262144],   // ⌃F2
        8:  [65535, 99,  262144],   // ⌃F3
        9:  [65535, 118, 262144],   // ⌃F4
        10: [65535, 96,  262144],   // ⌃F5
        11: [65535, 97,  262144],   // ⌃F6
        27: [96,    50,  1048576],  // ⌘`
        57: [65535, 100, 262144],   // ⌃F8
        // Accessibility
        59: [65535, 96,  1048576],  // ⌘F5 (VoiceOver)
    ]

    /// Parameters for IDs that are **disabled** by default; plist entry with
    /// valid params means the user customised (and/or re-enabled) them.
    private static let disabledByDefault: [Int: [Int]] = [
        // Input Sources
        60: [32, 49, 262144],       // ⌃Space
        61: [32, 49, 786432],       // ⌃⌥Space
        // Spaces (Switch to Space 1–10; IDs 118–127 from DefaultSpacesShortcuts.xml)
        118: [49, 18, 262144],      // ⌃1
        119: [50, 19, 262144],      // ⌃2
        120: [51, 20, 262144],      // ⌃3
        121: [52, 21, 262144],      // ⌃4
        122: [53, 23, 262144],      // ⌃5
        123: [54, 22, 262144],      // ⌃6
        124: [55, 26, 262144],      // ⌃7
        125: [56, 28, 262144],      // ⌃8
        126: [57, 25, 262144],      // ⌃9
        127: [48, 29, 262144],      // ⌃0
    ]

    // MARK: - Display tables

    private static let actionNames: [Int: String] = [
        // Spotlight
        64:  "Show Spotlight Search",
        65:  "Show Finder Search Window",
        // Screenshots
        28:  "Save Picture of Entire Screen",
        29:  "Copy Picture of Entire Screen",
        30:  "Save Picture of Selected Area",
        31:  "Copy Picture of Selected Area",
        184: "Screenshot and Recording Options",
        // Mission Control
        32:  "Mission Control",
        33:  "Application Windows",
        36:  "Show Desktop",
        // Keyboard Navigation
        7:   "Move Focus to Menu Bar",
        8:   "Move Focus to Dock",
        9:   "Move Focus to Active Window",
        10:  "Move Focus to Window Toolbar",
        11:  "Move Focus to Floating Window",
        27:  "Move Focus to Next Window",
        57:  "Move Focus to Status Menus",
        // Input Sources
        60:  "Select Previous Input Source",
        61:  "Select Next Input Source",
        // Accessibility
        59:  "Turn VoiceOver On/Off",
        // Spaces
        118: "Switch to Space 1",
        119: "Switch to Space 2",
        120: "Switch to Space 3",
        121: "Switch to Space 4",
        122: "Switch to Space 5",
        123: "Switch to Space 6",
        124: "Switch to Space 7",
        125: "Switch to Space 8",
        126: "Switch to Space 9",
        127: "Switch to Space 10",
    ]

    private static let groupOrder: [(String, [Int])] = [
        ("Spotlight",            [64, 65]),
        ("Screenshots",          [28, 29, 30, 31, 184]),
        ("Mission Control",      [32, 33, 36]),
        ("Keyboard Navigation",  [7, 8, 9, 10, 11, 27, 57]),
        ("Input Sources",        [60, 61]),
        ("Accessibility",        [59]),
        ("Spaces",               [118, 119, 120, 121, 122, 123, 124, 125, 126, 127]),
    ]
}
