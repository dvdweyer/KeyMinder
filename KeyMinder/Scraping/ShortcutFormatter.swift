// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation

/// Converts the raw key-equivalent attributes reported by the Accessibility API
/// into a human-readable shortcut string such as "⇧⌘N" or "⌃→".
enum ShortcutFormatter {

    /// Builds a shortcut string from an NSEvent — used to match a key press
    /// against the `Shortcut.keys` strings in the visible shortcuts list.
    static func keys(from event: NSEvent) -> String? {
        keys(keyCode: event.keyCode,
             modifierFlags: event.modifierFlags,
             charactersIgnoringModifiers: event.characters(byApplyingModifiers: []))
    }

    /// Testable overload: accepts raw values rather than an NSEvent.
    static func keys(keyCode: UInt16,
                     modifierFlags: NSEvent.ModifierFlags,
                     charactersIgnoringModifiers: String?) -> String? {
        var mods = ""
        if modifierFlags.contains(.control) { mods += "⌃" }
        if modifierFlags.contains(.option)  { mods += "⌥" }
        if modifierFlags.contains(.shift)   { mods += "⇧" }
        if modifierFlags.contains(.command) { mods += "⌘" }

        // Special keys (arrows, F-keys, Return, Delete, etc.) via hardware key code.
        if let sym = virtualKeyMap[Int(keyCode)] {
            return mods + sym
        }
        // Regular printable characters via the layout-adjusted unmodified character.
        guard let chars = charactersIgnoringModifiers,
              let scalar = chars.unicodeScalars.first else { return nil }
        let v = scalar.value
        if v >= 0xF700, let sym = functionKeyMap[v] { return mods + sym }
        if v == 0x20 { return mods + "Space" }
        if v >= 0x21 && v <= 0x7E { return mods + chars.uppercased() }
        return nil
    }

    /// Returns a formatted shortcut, or `nil` if the menu item has no key equivalent.
    static func format(cmdChar: String?, virtualKey: Int?, glyph: Int?, modifiers: Int) -> String? {
        guard let key = keySymbol(cmdChar: cmdChar, virtualKey: virtualKey, glyph: glyph) else {
            return nil
        }
        return modifierString(modifiers) + key
    }

    /// Decodes the `AXMenuItemCmdModifiers` mask.
    ///
    /// Command is implied unless the "no command" bit (8) is set; the remaining
    /// bits are shift (1), option (2) and control (4). Symbols are emitted in the
    /// conventional macOS order: ⌃⌥⇧⌘.
    private static func modifierString(_ modifiers: Int) -> String {
        var result = ""
        if modifiers & 4 != 0 { result += "⌃" }
        if modifiers & 2 != 0 { result += "⌥" }
        if modifiers & 1 != 0 { result += "⇧" }
        if modifiers & 8 == 0 { result += "⌘" }
        return result
    }

    private static func keySymbol(cmdChar: String?, virtualKey: Int?, glyph: Int?) -> String? {
        if let cmdChar, let scalar = cmdChar.unicodeScalars.first {
            let v = scalar.value
            switch v {
            case 0xF700...:           // NSEvent function-key private-use range
                if let mapped = functionKeyMap[v] { return mapped }
            case 0x09:                return "⇥"   // tab
            case 0x0D, 0x03:          return "↩"   // return / enter
            case 0x1B:                return "⎋"   // escape
            case 0x08, 0x7F:          return "⌫"   // backspace
            case 0x20:                return "Space"
            case 0x21...0x7E:         return String(scalar).uppercased()
            default:                  break
            }
        }
        if let glyph, glyph != 0, let mapped = glyphMap[glyph] {
            return mapped
        }
        if let virtualKey, let mapped = virtualKeyMap[virtualKey] {
            return mapped
        }
        return nil
    }

    /// NSEvent function-key constants (0xF700+) sometimes reported via `cmdChar`.
    private static let functionKeyMap: [UInt32: String] = [
        0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→",
        0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟",
        0xF704: "F1", 0xF705: "F2", 0xF706: "F3", 0xF707: "F4",
        0xF708: "F5", 0xF709: "F6", 0xF70A: "F7", 0xF70B: "F8",
        0xF70C: "F9", 0xF70D: "F10", 0xF70E: "F11", 0xF70F: "F12",
        0xF710: "F13", 0xF711: "F14", 0xF712: "F15", 0xF713: "F16",
        0xF714: "F17", 0xF715: "F18", 0xF716: "F19", 0xF717: "F20",
    ]

    /// HIToolbox `kMenu*Glyph` constants (`AXMenuItemCmdGlyph`).
    private static let glyphMap: [Int: String] = [
        0x02: "⇥", 0x03: "⇤", 0x04: "⌅", 0x09: "Space",
        0x0A: "⌦", 0x0B: "↩", 0x0D: "↩", 0x11: "⌘",
        0x17: "⌫", 0x1B: "⎋", 0x1C: "⌧",
        0x62: "⇞", 0x63: "⇪", 0x64: "←", 0x65: "→",
        0x66: "↖", 0x68: "↑", 0x69: "↘", 0x6A: "↓", 0x6B: "⇟",
    ]

    /// Hardware key codes (`AXMenuItemCmdVirtualKey`) for keys without a char.
    private static let virtualKeyMap: [Int: String] = [
        0x24: "↩", 0x4C: "⌅", 0x30: "⇥", 0x31: "Space",
        0x33: "⌫", 0x75: "⌦", 0x35: "⎋", 0x47: "⌧",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7E: "↑", 0x7D: "↓",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16",
        0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]
}
