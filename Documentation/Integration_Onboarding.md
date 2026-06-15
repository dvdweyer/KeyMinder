# KeyMinder Integration Guide for App Developers

KeyMinder shows users the active keyboard shortcuts of the frontmost app. If your app registers **global hotkeys** — shortcuts that work system-wide regardless of which app is in focus — you can make those visible in KeyMinder too. All it takes is writing a small JSON file.

---

## How it works

When a KeyMinder user opens the popup, KeyMinder reads all `.json` files from:

```
~/Library/Application Support/KeyMinder/Integrations/
```

Each file produces a section in the popup labelled with your app's name, showing your registered shortcuts. There is no IPC, no daemon, no API to call at runtime — just a JSON file on disk. The file is read fresh on every popup open, so updates take effect immediately the next time the user opens KeyMinder.

---

## Quick start

**1. Create the Integrations directory** (if it doesn't exist yet):

```
~/Library/Application Support/KeyMinder/Integrations/
```

**2. Write your registration file** at:

```
~/Library/Application Support/KeyMinder/Integrations/<your-bundle-id>.json
```

For example, `com.raycast.macos.json`:

```json
{
  "appName": "Raycast",
  "bundleIdentifier": "com.raycast.macos",
  "shortcuts": [
    { "title": "Show Raycast",     "keys": "⌥Space"  },
    { "title": "Show File Search", "keys": "⌥⇧Space" },
    { "title": "Show Clipboard",   "keys": "⌥⌘C"     }
  ]
}
```

That's it. The next time the user opens KeyMinder, your app's shortcuts appear in the popup.

---

## JSON schema

| Field | Type | Required | Description |
|---|---|---|---|
| `appName` | string | ✓ | Display name shown as the section header in the popup. |
| `bundleIdentifier` | string | — | Your app's bundle ID. Informational only — the filename is what KeyMinder uses as a key. |
| `shortcuts` | array | ✓ | The list of shortcuts to display. May be empty (produces no section). |

Each entry in `shortcuts`:

| Field | Type | Required | Description |
|---|---|---|---|
| `title` | string | ✓ | The action name, e.g. `"Show File Search"`. |
| `keys` | string | ✓ | The key combination as a glyph string, e.g. `"⌥⇧Space"`. Rendered as-is in the popup key badge. |
| `group` | string | — | Optional sub-group name. Shortcuts with the same `group` value are displayed under a shared sub-header, like a submenu. Omit for top-level (ungrouped) items. |

---

## Formatting the `keys` string

The `keys` string is displayed exactly as written — KeyMinder does not parse or reformat it. Follow macOS convention for consistency with the app's own menu shortcuts:

**Modifier order:** ⌃ ⌥ ⇧ ⌘ (Control, Option, Shift, Command), then the key.

**Modifier glyphs:**

| Key | Glyph | Unicode |
|---|---|---|
| Control | ⌃ | U+2303 |
| Option / Alt | ⌥ | U+2325 |
| Shift | ⇧ | U+21E7 |
| Command | ⌘ | U+2318 |

**Key examples:**

| Shortcut | `keys` value |
|---|---|
| ⌥Space | `"⌥Space"` |
| ⇧⌘K | `"⇧⌘K"` |
| ⌃⌥⇧⌘P | `"⌃⌥⇧⌘P"` |
| ⌘, (comma) | `"⌘,"` |
| ⌘Delete | `"⌘⌫"` or `"⌘Delete"` |
| F5 | `"F5"` |
| ⌘↑ | `"⌘↑"` |

Use uppercase letters (`"⌘N"` not `"⌘n"`). For Space, write the word `Space` — the popup renders it as a label just like macOS menus do.

---

## Using groups

Use `group` to organise shortcuts under sub-headers within your section — the same way KeyMinder renders submenus for a native app's menu bar. Shortcuts with no `group` appear first, above any named groups.

```json
{
  "appName": "Alfred",
  "bundleIdentifier": "com.runningwithcrayons.Alfred",
  "shortcuts": [
    { "title": "Show Alfred",          "keys": "⌥Space",  "group": "General"    },
    { "title": "Show File Navigation", "keys": "⌥⌘Space", "group": "General"    },
    { "title": "Show Clipboard",       "keys": "⌥⌘C",     "group": "Features"   },
    { "title": "Show Snippets",        "keys": "⌥⌘S",     "group": "Features"   },
    { "title": "Show Universal Actions","keys": "⌥⌘\\",   "group": "Features"   }
  ]
}
```

Groups appear in the order their first shortcut is encountered — no need to sort entries by group in the JSON.

---

## Swift sample code

The simplest approach is to write the registration file at launch and update it whenever the user changes a shortcut. Here is a self-contained helper you can drop into your app:

```swift
import Foundation

struct KeyMinderRegistration {

    struct Shortcut: Encodable {
        let title: String
        let keys: String
        let group: String?

        init(_ title: String, keys: String, group: String? = nil) {
            self.title = title
            self.keys = keys
            self.group = group
        }
    }

    private struct Payload: Encodable {
        let appName: String
        let bundleIdentifier: String
        let shortcuts: [Shortcut]
    }

    /// Writes (or updates) the KeyMinder registration file for this app.
    /// Call this at launch and whenever the user changes a hotkey.
    static func register(appName: String, shortcuts: [Shortcut]) {
        guard let dir = integrationsDirectory(create: true),
              let bundleID = Bundle.main.bundleIdentifier else { return }

        let payload = Payload(appName: appName, bundleIdentifier: bundleID, shortcuts: shortcuts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else { return }
        let file = dir.appendingPathComponent("\(bundleID).json")
        try? data.write(to: file, options: .atomic)
    }

    /// Removes this app's registration file.
    /// Call this when the user uninstalls your app or opts out.
    static func unregister() {
        guard let dir = integrationsDirectory(create: false),
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let file = dir.appendingPathComponent("\(bundleID).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: -

    private static func integrationsDirectory(create: Bool) -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = support.appendingPathComponent("KeyMinder/Integrations", isDirectory: true)
        if create && !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir,
                withIntermediateDirectories: true, attributes: nil)
        }
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
}
```

**Usage — register at launch:**

```swift
// AppDelegate.swift or @main entry point

func applicationDidFinishLaunching(_ notification: Notification) {
    // ...your existing setup...

    KeyMinderRegistration.register(appName: "Raycast", shortcuts: [
        .init("Show Raycast",       keys: "⌥Space",  group: "General"),
        .init("Show File Search",   keys: "⌥⇧Space", group: "General"),
        .init("Show Clipboard",     keys: "⌥⌘C",     group: "Clipboard"),
        .init("Show Snippets",      keys: "⌥⌘S",     group: "Clipboard"),
    ])
}
```

**Usage — update when the user changes a hotkey:**

```swift
// Wherever you persist a hotkey change:

func userDidChangeHotkey() {
    // re-register with the updated shortcuts
    KeyMinderRegistration.register(appName: "Raycast", shortcuts: currentShortcuts())
}
```

**Usage — clean up on uninstall** (if your app has a dedicated uninstaller or teardown path):

```swift
KeyMinderRegistration.unregister()
```

---

## Testing your integration

1. **Build and run your app** so it writes the registration file.

2. **Verify the file was created:**

   ```sh
   cat ~/Library/Application\ Support/KeyMinder/Integrations/com.your.app.json
   ```

3. **Open KeyMinder** (⌥⌘K or your configured trigger). Your app's shortcuts should appear as a new section at the bottom of the popup, below the frontmost app's menu shortcuts.

4. **If the section is missing**, check:
   - The Integrations directory exists (see step 2).
   - The JSON is valid — paste it into [jsonlint.com](https://jsonlint.com) or run `python3 -m json.tool com.your.app.json` in Terminal.
   - The user has not toggled off **Settings → Popup → Show registered app shortcuts**.

5. **View KeyMinder's log** for any parse errors:

   ```sh
   /usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder'"
   ```

   Malformed or unreadable files are logged as `ThirdPartyRegistry: malformed <filename>` or `ThirdPartyRegistry: unreadable <filename>`.

---

## Keeping shortcuts in sync

Because the file is read on every popup open, there is no delay between writing an update and the user seeing it — just write the file and the next popup open reflects the change.

A good pattern is to always re-write the full file from your in-memory state:

- **At launch** — write the current shortcut state.
- **When the user changes a hotkey** — re-write the full file.
- **When the user resets to defaults** — re-write the full file with default values.

There is no need to diff against the previous file content. Writing atomically (`.atomic` option in Swift's `Data.write`) ensures KeyMinder never reads a half-written file.

---

## Sandbox note

If your app runs in the macOS **App Sandbox**, writing to `~/Library/Application Support/KeyMinder/` requires the `com.apple.security.temporary-exception.files.absolute-path.read-write` entitlement for that path. In practice, apps that register global hotkeys (via Carbon `RegisterEventHotKey` or `CGEventTap`) cannot be sandboxed — so this is unlikely to affect you.

---

## Questions / feedback

Open an issue or start a discussion at [github.com/dvdweyer/KeyMinder](https://github.com/dvdweyer/KeyMinder). We are happy to help you get integrated.
