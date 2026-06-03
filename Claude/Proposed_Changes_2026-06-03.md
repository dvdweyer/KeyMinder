# App Review — 2026-06-03

## Summary

KeyMinder v0.1.61 is a mature, well-structured macOS 14+ menu-bar shortcut viewer. The codebase is clean: zero build warnings, all 46 unit tests pass, concurrency is consistently `@MainActor`-isolated, and every finding from the 2026-06-01 security audit and 2026-06-02 code review has been resolved — including the test-suite compile failure (PC-001), the visibleShortcuts cache (PC-004), the `@MainActor` annotation on `FrontmostAppMonitor` (PC-005), and all log-privacy fixes. The `as!` force-cast in `MenuScraper.element(_:_:)` is intentionally retained: the code comment correctly explains that `as?` on a CF type alias always returns non-nil, making `CFGetTypeID` the real type guard. Seven new low-severity findings are identified this cycle, centered on accessibility completeness and defensive coding.

---

## Build & Runtime Notes

| | |
|---|---|
| Build result | ✅ **BUILD SUCCEEDED** — 0 warnings, 0 errors |
| Test result | ✅ **ALL TESTS PASSED** — 46 tests across 9 suites |
| Xcode SDK | macOS 26 (target arm64-apple-macos14.0) |
| Swift version | 5.0 |
| Version | 0.1.61 |

**Carry-over items fully resolved since 2026-06-02 review:**
- PC-001 (`AppShortcuts.fixture` compile error) — fixed
- PC-002 (`as!` force cast) — retained intentionally with explanatory comment
- PC-003 (onboarding text) — fixed
- PC-004 (`visibleShortcuts` caching) — fixed
- PC-005 (`@MainActor` on `FrontmostAppMonitor`) — fixed
- PC-006 (DoubleTap + PopupFilterModel tests) — fixed; 46 tests now pass
- All security fixes from `Security_Fixes_2026-06-01.md` — applied (log privacy, recursion depth, security comment)

---

## Proposed Changes

### [PC-001] — ModifierToggle buttons missing accessibility state

**Severity:** Medium  
**Dimension:** Usability & accessibility  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` — `ModifierToggle` (~line 511)  
**Model:** Sonnet  

**Context:**  
The modifier filter buttons (⌃ ⌥ ⇧ ⌘) can be toggled on or off, but VoiceOver announces only their label (e.g. "Command") without indicating whether the filter is currently active. A user relying on VoiceOver cannot determine which modifier filters are enabled. Adding `.accessibilityAddTraits(.isSelected)` when active, combined with an `.accessibilityValue`, gives the screen reader the state it needs to speak "Command, selected" vs "Command, not selected".

**Prompt:**  
In `KeyMinder/UI/Popup/PopupRootView.swift` (non-sandboxed macOS 14+ app, v0.1.61), find `private struct ModifierToggle`. Its `body` contains a `Button` that uses a `Text` label with a glyph character.

Add the following two accessibility modifiers to the `Button` (inside `ModifierToggle.body`, after the `.buttonStyle(.plain)` modifier):

```swift
.accessibilityAddTraits(isActive ? .isSelected : [])
.accessibilityValue(isActive ? "on" : "off")
```

This lets VoiceOver announce the button as "Command, on, button" or "Command, off, button" depending on filter state. No other code changes.

After the change:
1. Build the project:
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
     -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | tail -5
   ```
2. Run all tests and confirm they still pass.
3. Bump `MARKETING_VERSION` patch number in `project.pbxproj` and tag `vX.Y.Z` per CLAUDE.md convention. Build to `/tmp` (never into the iCloud project folder).

---

### [PC-002] — `spokenKeys` function has no unit tests

**Severity:** Low  
**Dimension:** Test coverage  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` (~line 544), new `KeyMinderTests/SpokenKeysTests.swift`  
**Model:** Sonnet  

**Context:**  
`spokenKeys(_:)` is a pure, non-trivial function that generates VoiceOver accessibility labels for shortcut key strings. Its logic includes: a character map for modifier glyphs and special keys, a lookahead loop to aggregate multi-character Fn keys ("F12"), and an uppercasing fallback for regular letters. It has zero test coverage. The Fn-key accumulation path is particularly easy to get wrong (off-by-one on digit lookahead). The function is `private` inside the popup file, so it needs to be promoted to `internal` or accessed via `@testable import` — the latter is already used by every other test file in the project.

**Prompt:**  
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.61), add a unit test file for the `spokenKeys` function.

**Step 1 — Make the function testable.** In `KeyMinder/UI/Popup/PopupRootView.swift`, change `private func spokenKeys` to `func spokenKeys` (package-internal). No other changes to this file.

**Step 2 — Create `KeyMinderTests/SpokenKeysTests.swift`** with `@testable import KeyMinder`. The Xcode project uses a file-system-synchronized group (objectVersion 70) so the file is picked up automatically.

Write tests for the following cases (at minimum):
- `spokenKeys("")` returns `""`.
- `spokenKeys("⌘")` returns `"Command"`.
- `spokenKeys("⇧⌘N")` returns `"Shift Command N"`.
- `spokenKeys("⌃⌥⇧⌘X")` returns `"Control Option Shift Command X"`.
- `spokenKeys("↩")` returns `"Return"`.
- `spokenKeys("⎋")` returns `"Escape"`.
- `spokenKeys("⌫")` returns `"Delete"`.
- `spokenKeys("⇥")` returns `"Tab"`.
- `spokenKeys("F5")` returns `"F5"` (single Fn key token, not "F" + "5").
- `spokenKeys("⌘F12")` returns `"Command F12"` (two-digit Fn).
- `spokenKeys("↑")` returns `"Up Arrow"`.
- `spokenKeys("→")` returns `"Right Arrow"`.
- `spokenKeys("Space")` returns `"Space"` (the literal word, not individual chars).

After creating the file, run the full test suite:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | \
  grep -E "(PASSED|FAILED|error:)"
```
All tests must pass. Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-003] — VoiceOver label has trailing comma for no-shortcut rows

**Severity:** Low  
**Dimension:** Usability & accessibility  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` — `ShortcutRow.body` (~line 503)  
**Model:** Sonnet  

**Context:**  
`ShortcutRow` always builds its VoiceOver accessibility label as `"\(shortcut.title), \(spokenKeys(shortcut.keys))"`. In all-entries mode, menu items without a keyboard shortcut have `keys == ""`, so `spokenKeys("")` returns `""`. The label becomes `"Export, "` — a trailing comma followed by a space — which VoiceOver announces as "Export, " with a brief pause for the empty spoken segment. The label should be just the title when `keys` is empty.

**Prompt:**  
In `KeyMinder/UI/Popup/PopupRootView.swift` (non-sandboxed macOS 14+ app, v0.1.61), find `struct ShortcutRow`. In `body`, locate the `.accessibilityLabel` modifier (~line 503):

```swift
.accessibilityLabel("\(shortcut.title), \(spokenKeys(shortcut.keys))")
```

Replace it with:

```swift
.accessibilityLabel(
    shortcut.keys.isEmpty
        ? shortcut.title
        : "\(shortcut.title), \(spokenKeys(shortcut.keys))"
)
```

No other changes. Build and run all tests:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | tail -5
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-004] — HotkeyManager checks only `eventID`, not `signature`, in Carbon handler

**Severity:** Polish  
**Dimension:** Correctness  
**File(s):** `KeyMinder/Settings/HotkeyManager.swift` (~line 94)  
**Model:** Sonnet  

**Context:**  
The Carbon event handler in `HotkeyManager` fires when any `kEventHotKeyPressed` event reaches the application event target. It guards with `hkID.id == HotkeyManager.eventID` (checking `id == 1`) but does not check `hkID.signature`. The `EventHotKeyID` struct has both a `signature` (four-char code, used to namespace IDs) and an `id` field precisely to prevent collisions between different parts of the same process. If a future feature registers a second hotkey with a different signature but the same numeric ID (`1`), the current check would incorrectly fire for both. Checking both fields is the documented correct pattern for Carbon hotkey handlers.

**Prompt:**  
In `KeyMinder/Settings/HotkeyManager.swift` (non-sandboxed macOS 14+ app, v0.1.61), find the C callback closure passed to `InstallEventHandler`. Locate the conditional:

```swift
if hkID.id == HotkeyManager.eventID {
```

Replace it with:

```swift
if hkID.signature == HotkeyManager.signature && hkID.id == HotkeyManager.eventID {
```

No other changes. Build and confirm BUILD SUCCEEDED:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | tail -5
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-005] — `NSApp.activate(ignoringOtherApps:)` deprecated in macOS 14

**Severity:** Polish  
**Dimension:** Swift/SwiftUI best practices  
**File(s):** `KeyMinder/AppDelegate.swift` (~line 232), `KeyMinder/UI/Settings/SettingsView.swift` (~line 16)  
**Model:** Sonnet  

**Context:**  
`NSApplication.activate(ignoringOtherApps:)` was deprecated in macOS 14.0; the replacement is `NSApp.activate()` (no parameter). The current project build reports 0 warnings, which suggests the warning may be suppressed by the build system or the xcodebuild grep filter. Two call sites exist: `AppDelegate.showAbout()` and `SettingsWindowController.show()`. Using the modern API removes the deprecation and aligns with the macOS 14+ deployment target.

**Prompt:**  
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.61), replace all uses of `NSApp.activate(ignoringOtherApps: true)` with `NSApp.activate()`.

There are two call sites:
1. `KeyMinder/AppDelegate.swift` in `showAbout()`.
2. `KeyMinder/UI/Settings/SettingsView.swift` in `SettingsWindowController.show()`.

In each file, replace:
```swift
NSApp.activate(ignoringOtherApps: true)
```
with:
```swift
NSApp.activate()
```

Build and confirm BUILD SUCCEEDED with 0 warnings:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | \
  grep -E "(warning:|error:|SUCCEEDED|FAILED)"
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-006] — Double AX call for empty-submenu item count logging

**Severity:** Polish  
**Dimension:** Performance  
**File(s):** `KeyMinder/Scraping/MenuScraper.swift` — `collectGroups` (~line 88), `collectShortcutsFlat` (~line 130)  
**Model:** Sonnet  

**Context:**  
When a submenu yields 0 shortcuts, both `collectGroups` and `collectShortcutsFlat` call `children(submenu)` a second time to get the raw child count for the diagnostic log message. `children(submenu)` makes a synchronous AX IPC call (up to 1 s each call, capped by `AXUIElementSetMessagingTimeout`). For submenus that return empty, `children(menu)` inside `collectShortcutsFlat` already fetched the children — returning `[]`. The log then calls `children(submenu).count` again, doubling the AX round-trip for every lazy-loaded or empty submenu. Changing `collectShortcutsFlat` to return the raw child count alongside the result eliminates the second IPC call.

**Prompt:**  
In `KeyMinder/Scraping/MenuScraper.swift` (non-sandboxed macOS 14+ app, v0.1.61), eliminate the redundant second `children(submenu)` AX call when logging empty submenus.

**Change 1 — `collectShortcutsFlat` return type.**

Change the signature and return type from:
```swift
private static func collectShortcutsFlat(
    in menu: AXUIElement, includeAll: Bool = false, depth: Int = 0
) -> [Shortcut]
```
to:
```swift
private static func collectShortcutsFlat(
    in menu: AXUIElement, includeAll: Bool = false, depth: Int = 0
) -> (shortcuts: [Shortcut], rawChildCount: Int)
```

At the top of the function body, fetch and store children once:
```swift
let menuChildren = children(menu)
```
then iterate `menuChildren` instead of calling `children(menu)` again. At the end of the function, `return (result, menuChildren.count)`.

**Change 2 — update all call sites.**

In `collectGroups`, the call site:
```swift
let submenuItems = collectShortcutsFlat(in: submenu, includeAll: includeAll)
if !submenuItems.isEmpty {
    named.append(ShortcutGroup(title: title, shortcuts: submenuItems))
} else {
    let itemCount = children(submenu).count
    let hint = itemCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
```
becomes:
```swift
let (submenuItems, rawChildCount) = collectShortcutsFlat(in: submenu, includeAll: includeAll)
if !submenuItems.isEmpty {
    named.append(ShortcutGroup(title: title, shortcuts: submenuItems))
} else {
    let hint = rawChildCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
```

In `collectShortcutsFlat`'s own recursive call site:
```swift
let sub = collectShortcutsFlat(in: submenu, includeAll: includeAll, depth: depth + 1)
if sub.isEmpty {
    let itemCount = children(submenu).count
    let hint = itemCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
result.append(contentsOf: sub)
```
becomes:
```swift
let (sub, subChildCount) = collectShortcutsFlat(in: submenu, includeAll: includeAll, depth: depth + 1)
if sub.isEmpty {
    let hint = subChildCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
result.append(contentsOf: sub)
```

Build, run tests, confirm BUILD SUCCEEDED 0 warnings and all tests pass:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | \
  grep -E "(warning:|error:|PASSED|FAILED)"
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-007] — `SettingsWindowController.init()` creates two `SettingsView` instances

**Severity:** Polish  
**Dimension:** Performance  
**File(s):** `KeyMinder/UI/Settings/SettingsView.swift` — `SettingsWindowController.init()` (~line 21)  
**Model:** Sonnet  

**Context:**  
`SettingsWindowController.init()` creates a throwaway `NSHostingController(rootView: SettingsView())` solely to measure the natural content height, then creates a second `NSHostingView(rootView: SettingsView())` for actual display. Each `SettingsView()` construction initializes a `SettingsModel` instance, which reads from `UserDefaults` and queries `LoginItemManager.shared.isEnabled` (an `SMAppService` call). The measurement controller is discarded immediately after `.sizeThatFits` returns. Since `SettingsView` has no data-driven dynamic sizing (all content is fixed), the measured height is constant. Reusing a single `NSHostingController` for both measurement and display avoids the wasted initialization.

**Prompt:**  
In `KeyMinder/UI/Settings/SettingsView.swift` (non-sandboxed macOS 14+ app, v0.1.61), refactor `SettingsWindowController.init()` to create only one `SettingsView()` instance.

Current code:
```swift
private init() {
    let measured = NSHostingController(rootView: SettingsView())
        .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
        .height.rounded()
    let contentHeight = min(max(measured, 280), 600)

    let hosting = NSHostingView(rootView: SettingsView())
    ...
}
```

Replace with:
```swift
private init() {
    let controller = NSHostingController(rootView: SettingsView())
    let measured = controller
        .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
        .height.rounded()
    let contentHeight = min(max(measured, 280), 600)

    let hosting = controller.view
    ...
}
```

`NSHostingController.view` is the `NSView` used by `NSHostingController` internally; it can be assigned directly as the window's `contentView`. The `@State SettingsModel` is created only once. No other changes.

Build and confirm BUILD SUCCEEDED:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | tail -5
```
Open Settings from the context menu and confirm the window appears and all toggles/fields work correctly. Bump `MARKETING_VERSION` and tag. Build to `/tmp`.
