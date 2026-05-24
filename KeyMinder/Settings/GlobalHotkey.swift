import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut stored as a Carbon key code + modifier mask.
struct GlobalHotkey: Codable, Equatable {
    /// Virtual key code (matches CGKeyCode / kVK_* constants).
    let keyCode: UInt32
    /// Carbon modifier flags for use with RegisterEventHotKey
    /// (cmdKey, shiftKey, optionKey, controlKey bitmask).
    let carbonModifiers: UInt32
    /// Pre-formatted display string built at recording time, e.g. "⌥⌘K".
    let displayString: String
}

// MARK: - Factory

extension GlobalHotkey {

    /// Creates a GlobalHotkey from a raw NSEvent.
    /// Returns `nil` when the event lacks at least one "strong" modifier (⌘ / ⌥ / ⌃).
    static func from(event: NSEvent) -> GlobalHotkey? {
        let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let hasStrong = relevant.contains(.command)
                     || relevant.contains(.option)
                     || relevant.contains(.control)
        guard hasStrong else { return nil }

        let kc = UInt32(event.keyCode)
        return GlobalHotkey(
            keyCode: kc,
            carbonModifiers: carbonFlags(from: relevant),
            displayString: displayString(keyCode: kc, modifiers: relevant, event: event)
        )
    }

    // MARK: Carbon conversion

    private static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        return c
    }

    // MARK: Display string

    private static func displayString(keyCode: UInt32,
                                      modifiers: NSEvent.ModifierFlags,
                                      event: NSEvent) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyLabel(keyCode: keyCode, event: event)
        return s
    }

    private static func keyLabel(keyCode: UInt32, event: NSEvent) -> String {
        switch keyCode {
        // Whitespace / editing
        case 36: return "↩"   // Return
        case 48: return "⇥"   // Tab
        case 49: return "Space"
        case 51: return "⌫"   // Delete (backspace)
        case 53: return "⎋"   // Escape
        case 76: return "⌤"   // Enter (numpad)
        // Navigation
        case 115: return "↖"  // Home
        case 116: return "⇞"  // Page Up
        case 117: return "⌦"  // Forward Delete
        case 119: return "↘"  // End
        case 121: return "⇟"  // Page Down
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        // Function keys
        case 122: return "F1";  case 120: return "F2"
        case 99:  return "F3";  case 118: return "F4"
        case 96:  return "F5";  case 97:  return "F6"
        case 98:  return "F7";  case 100: return "F8"
        case 101: return "F9";  case 109: return "F10"
        case 103: return "F11"; case 111: return "F12"
        // Regular keys: use layout-aware character from the event
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}

// MARK: - UserDefaults

extension UserDefaults {
    private static let hotkeyKey = "globalHotkey"

    var globalHotkey: GlobalHotkey? {
        get {
            guard let data = data(forKey: Self.hotkeyKey) else { return nil }
            return try? JSONDecoder().decode(GlobalHotkey.self, from: data)
        }
        set {
            if let hotkey = newValue,
               let data = try? JSONEncoder().encode(hotkey) {
                set(data, forKey: Self.hotkeyKey)
            } else {
                removeObject(forKey: Self.hotkeyKey)
            }
        }
    }
}
