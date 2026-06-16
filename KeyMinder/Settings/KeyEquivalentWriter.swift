// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Carbon.HIToolbox
import os

/// Writes macOS "App Shortcuts" by editing the `NSUserKeyEquivalents` dictionary
/// in a target app's preference domain — the same store System Settings → Keyboard
/// → Keyboard Shortcuts → App Shortcuts writes to.
///
/// The dictionary maps a menu item's exact title to an encoded key-equivalent
/// string (e.g. `"New Note" → "@$n"`, where `^`=⌃ `~`=⌥ `$`=⇧ `@`=⌘). This is the
/// inverse of `SystemShortcutsProvider.formatUserKeyEquivalent(_:)`, which decodes
/// the same format for display.
///
/// Caveats (intrinsic to the OS feature, surfaced in the UI):
/// - The change takes effect only after the **target app relaunches** — Cocoa applies
///   `NSUserKeyEquivalents` when it builds the menu.
/// - Only **AppKit** menus honour it; Electron/Java/some Catalyst apps ignore it (so
///   does System Settings' own App Shortcuts pane).
/// - Writing goes through the `CFPreferences` API (not the raw `.plist`) so `cfprefsd`
///   stays authoritative and does not clobber the change.
enum KeyEquivalentWriter {

    private static let key = "NSUserKeyEquivalents" as CFString

    /// `nil` `bundleID` targets the "All Applications" scope (`.GlobalPreferences`).
    private static func domain(_ bundleID: String?) -> CFString {
        (bundleID as CFString?) ?? kCFPreferencesAnyApplication
    }

    // MARK: - Encoding

    /// Encodes a key combination into an `NSUserKeyEquivalents` value string.
    ///
    /// Pure (no `NSEvent`, no keyboard-layout lookup) so it can be unit-tested directly.
    /// `base` must be the **unshifted** key character (e.g. `1`, not `!`; `/`, not `?`):
    /// macOS stores Shift as a separate `$` prefix over the base character, matching the
    /// in-repo decoder `SystemShortcutsProvider.formatUserKeyEquivalent`.
    /// Returns `nil` for a combo with no ⌃/⌥/⌘ modifier (a bare or Shift-only key is not
    /// a valid menu equivalent and would shadow plain typing).
    static func encode(modifiers: NSEvent.ModifierFlags, base: Character) -> String? {
        guard modifiers.contains(.control) || modifiers.contains(.option)
                || modifiers.contains(.command) else { return nil }

        // Modifier order matches macOS's canonical storage (Control, Option, Command,
        // Shift) — the in-repo decoder example "@$/" confirms Command precedes Shift.
        var v = ""
        if modifiers.contains(.control) { v += "^" }
        if modifiers.contains(.option)  { v += "~" }
        if modifiers.contains(.command) { v += "@" }
        if modifiers.contains(.shift)   { v += "$" }
        // Letters are stored lowercase (Shift is carried by the "$" prefix).
        v.append(base.isASCII && base.isLetter ? Character(base.lowercased()) : base)
        return v
    }

    /// Builds the value string for a live key-down event, resolving the unshifted base
    /// character via the active keyboard layout. Falls back to `charactersIgnoringModifiers`
    /// for function/arrow keys (which carry their own private-use scalars).
    static func value(for event: NSEvent) -> String? {
        let base = baseCharacter(forKeyCode: event.keyCode)
            ?? event.charactersIgnoringModifiers?.first
        guard let base else { return nil }
        return encode(modifiers: event.modifierFlags, base: base)
    }

    /// The unshifted character a key produces on the current layout, or `nil` for
    /// modifier-only and non-printable keys (which the caller resolves another way).
    private static func baseCharacter(forKeyCode keyCode: UInt16) -> Character? {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
            ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let source,
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0,
              let ch = String(utf16CodeUnits: chars, count: length).first,
              let scalar = ch.unicodeScalars.first, scalar.value >= 0x20  // reject control chars
        else { return nil }
        return ch
    }

    // MARK: - Read / write

    /// The current `NSUserKeyEquivalents` dictionary for `bundleID` (or "All Applications").
    static func current(bundleID: String?) -> [String: String] {
        CFPreferencesCopyAppValue(key, domain(bundleID)) as? [String: String] ?? [:]
    }

    /// Whether `title` currently has a user-assigned key equivalent in this scope.
    static func hasEntry(title: String, bundleID: String?) -> Bool {
        current(bundleID: bundleID)[title] != nil
    }

    /// Assigns `value` (an encoded equivalent string) to `title`. Returns `false` if
    /// the write could not be confirmed.
    @discardableResult
    static func assign(title: String, value: String, bundleID: String?) -> Bool {
        write(title: title, value: value, bundleID: bundleID)
    }

    /// Removes any user-assigned equivalent for `title`. Returns `false` on failure.
    @discardableResult
    static func remove(title: String, bundleID: String?) -> Bool {
        write(title: title, value: nil, bundleID: bundleID)
    }

    private static func write(title: String, value: String?, bundleID: String?) -> Bool {
        guard !title.isEmpty else { return false }
        let app = domain(bundleID)
        var dict = current(bundleID: bundleID)
        dict[title] = value   // nil removes the key
        CFPreferencesSetAppValue(key, dict.isEmpty ? nil : (dict as CFDictionary), app)
        let ok = CFPreferencesAppSynchronize(app)
        if !ok {
            Logger.settings.error("Failed to write NSUserKeyEquivalents for domain \(String(describing: bundleID), privacy: .public)")
        }
        return ok
    }
}
