# App Review — 2026-06-07

## Summary

KeyMinder v0.1.79 is a mature, well-structured macOS 14+ menu-bar shortcut viewer. The codebase is in excellent health: 1 build warning (down from 0, introduced by a `nonisolated` annotation mismatch), all 46 unit tests pass, and every finding from the 2026-06-03 review cycle and the SK code-review has been resolved — including concurrent AX traversal prevention (SK-C), the `Dictionary` crash on duplicate section titles (SK-A), hotkey registration failure surfacing (SK-B), and `ModifierToggle` accessibility state (PC-001). This cycle's most significant finding is a **medium-severity correctness bug** in `spokenKeys(_:)`: the multi-character token `"Space"` output by `ShortcutFormatter` is parsed letter-by-letter, causing VoiceOver to announce Spotlight (⌘Space) as *"Command S P A C E"* instead of *"Command Space"*. The remaining items are low-severity carryovers from the prior cycle plus three new architectural/performance observations.

---

## Build & Runtime Notes

| | |
|---|---|
| Build result | ✅ **BUILD SUCCEEDED** — 1 warning, 0 errors |
| Test result | ✅ **ALL TESTS PASSED** — 46 tests |
| Xcode SDK | macOS 26 (arm64-apple-macos14.0) |
| Swift version | 5.0 |
| Version | 0.1.79 |

**Active warning (appears twice — one per build config):**
```
FrontmostAppMonitor.swift:14: warning: 'nonisolated(unsafe)' has no effect
on property 'observer', consider using 'nonisolated'
```

**Fully resolved since 2026-06-03:**
- **SK-A** (`measuredContent` empty-columns + `Dictionary` crash on duplicate section titles) — fixed
- **SK-B** (`HotkeyManager.register` returns `Bool`; Settings shows inline error) — fixed
- **SK-C** (`presentPopup` prevents concurrent AX traversals via drain-then-start) — fixed
- **PC-001** (`ModifierToggle` missing `.accessibilityAddTraits`/`.accessibilityValue`) — fixed

---

## Proposed Changes

### [PC-001] — `spokenKeys` mishandles the "Space" token

**Severity:** Medium  
**Dimension:** Correctness / Usability & accessibility  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` — `spokenKeys(_:)` (~line 675)  
**Model:** Sonnet  

**Context:**  
`ShortcutFormatter` outputs the 5-character string `"Space"` (not a literal space character `" "`) for the Space key — this occurs for ⌘Space (Spotlight), ⌃Space (Input Sources), and any user-defined shortcut bound to Space. The `spokenKeys` function maps the character `" "` → `"Space"`, but a raw space character never appears in a keys string, making that map entry dead code. The 5-letter word `"Space"` is parsed character-by-character, so `spokenKeys("⌘Space")` returns `"Command S P A C E"`. VoiceOver announces Spotlight's row as *"Show Spotlight Search, Command S P A C E, button"*.

**Prompt:**  
In `KeyMinder/UI/Popup/PopupRootView.swift` (non-sandboxed macOS 14+ app, v0.1.79), fix `spokenKeys(_:)` so the multi-character token `"Space"` is handled as a unit.

`ShortcutFormatter` outputs the word `"Space"` (not a space character) for the Space key via three code paths: `cmdChar 0x20` (line 39), `glyphMap[0x09]` (line 66), `virtualKeyMap[0x31]` (line 75). The current `map` entry `" ": "Space"` is dead code and should be removed.

Make two changes to `spokenKeys(_:)`:

**1. Remove the dead map entry** — delete `" ": "Space"` from the `map` dictionary.

**2. Add a prefix-match guard at the top of the `while` loop**, before `remaining = remaining.dropFirst()`:

```swift
while let ch = remaining.first {
    // "Space" is output as the 5-char word by ShortcutFormatter; match it
    // as a unit before falling through to single-character processing.
    if remaining.hasPrefix("Space") {
        tokens.append("Space")
        remaining = remaining.dropFirst(5)
        continue
    }
    remaining = remaining.dropFirst()
    // ... existing logic unchanged ...
}
```

No other changes. After the fix:
- `spokenKeys("Space")` → `"Space"`
- `spokenKeys("⌘Space")` → `"Command Space"`

Build and confirm 0 warnings:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | \
  grep -E "(warning:|error:|SUCCEEDED|FAILED)"
```
Bump `MARKETING_VERSION` in `project.pbxproj` and tag `vX.Y.Z` per CLAUDE.md convention. Build to `/tmp`.

---

### [PC-002] — `spokenKeys` function has no unit tests

**Severity:** Low  
**Dimension:** Test coverage  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` (~line 674), new `KeyMinderTests/SpokenKeysTests.swift`  
**Model:** Sonnet  

**Context:**  
`spokenKeys(_:)` is a pure, non-trivial function that generates VoiceOver accessibility labels. It has no unit tests. The `"Space"` token bug (PC-001, this cycle) went undetected because there was no test exercising it. The Fn-key accumulation path (lookahead for digits after "F") is similarly easy to get wrong. The function is `private` at file scope; it needs to be widened to package-internal for `@testable import` access, which all existing test files already use. The Xcode project uses a file-system-synchronized group (objectVersion 70) so new `.swift` files are picked up automatically.

**Note:** Assumes **PC-001 is applied first** — the `spokenKeys("Space")` and `spokenKeys("⌘Space")` test cases will fail on the unpatched version.

**Prompt:**  
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.79), add unit tests for `spokenKeys(_:)`.

**Step 1 — Make the function testable.** In `KeyMinder/UI/Popup/PopupRootView.swift`, change:
```swift
private func spokenKeys(_ keys: String) -> String {
```
to:
```swift
func spokenKeys(_ keys: String) -> String {
```
No other changes to this file.

**Step 2 — Create `KeyMinderTests/SpokenKeysTests.swift`** with `@testable import KeyMinder`. Write tests covering at minimum:

| Input | Expected output |
|---|---|
| `""` | `""` |
| `"⌘"` | `"Command"` |
| `"⇧⌘N"` | `"Shift Command N"` |
| `"⌃⌥⇧⌘X"` | `"Control Option Shift Command X"` |
| `"↩"` | `"Return"` |
| `"⎋"` | `"Escape"` |
| `"⌫"` | `"Delete"` |
| `"⇥"` | `"Tab"` |
| `"F5"` | `"F5"` |
| `"⌘F12"` | `"Command F12"` |
| `"↑"` | `"Up Arrow"` |
| `"→"` | `"Right Arrow"` |
| `"Space"` | `"Space"` *(requires PC-001)* |
| `"⌘Space"` | `"Command Space"` *(requires PC-001)* |

Run all tests and confirm they pass:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | \
  grep -E "(PASSED|FAILED|error:)"
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-003] — VoiceOver label has trailing comma for no-shortcut rows

**Severity:** Low  
**Dimension:** Usability & accessibility  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` — `ShortcutRow.body` (~line 602)  
**Model:** Sonnet  

**Context:**  
`ShortcutRow` always builds its VoiceOver label as `"\(shortcut.title), \(spokenKeys(shortcut.keys))"`. In all-entries mode, menu items with no keyboard shortcut have `keys == ""`, so `spokenKeys("")` returns `""`. The label becomes `"Export, "` — a trailing comma and space — which VoiceOver announces with an audible pause. The label should be just the title when `keys` is empty.

**Prompt:**  
In `KeyMinder/UI/Popup/PopupRootView.swift` (non-sandboxed macOS 14+ app, v0.1.79), find `struct ShortcutRow`. In `body`, locate the `.accessibilityLabel` modifier (~line 602):

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

### [PC-004] — `FrontmostAppMonitor` build warning: `nonisolated(unsafe)` has no effect

**Severity:** Low  
**Dimension:** Swift/SwiftUI best practices  
**File(s):** `KeyMinder/Monitoring/FrontmostAppMonitor.swift:14`  
**Model:** Sonnet  

**Context:**  
The current build produces two warnings (`nonisolated(unsafe)` has no effect on property `observer`; consider using `nonisolated`). The annotation was written to allow `deinit` (which is implicitly nonisolated) to read `observer` for unsubscribing. The compiler now says `nonisolated` alone is the correct spelling for this case — `nonisolated(unsafe)` is only meaningful for properties accessed from *unsynchronised* nonisolated contexts, which is not the case here. A one-word change silences both warnings and accurately expresses the intent.

**Prompt:**  
In `KeyMinder/Monitoring/FrontmostAppMonitor.swift` (non-sandboxed macOS 14+ app, v0.1.79), line 14, change:

```swift
nonisolated(unsafe) private var observer: NSObjectProtocol?
```
to:
```swift
nonisolated private var observer: NSObjectProtocol?
```

No other changes. Build and confirm **0 warnings, 0 errors**:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | \
  grep -E "(warning:|error:|SUCCEEDED|FAILED)"
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-005] — `HotkeyManager` Carbon handler checks `id` but not `signature`

**Severity:** Polish  
**Dimension:** Correctness  
**File(s):** `KeyMinder/Settings/HotkeyManager.swift` (~line 97)  
**Model:** Sonnet  

**Context:**  
The Carbon event handler fires when `kEventHotKeyPressed` reaches the application event target and guards with `hkID.id == HotkeyManager.eventID` (checking `id == 1`) without checking `hkID.signature`. `EventHotKeyID` has both `signature` (a four-char code that namespaces IDs across components) and `id`. If a future feature registers a second hotkey sharing the same numeric `id` with a different signature — or if a linked library happens to use ID 1 — the handler would fire incorrectly. Checking both fields is the documented correct pattern for Carbon hotkey handlers.

**Prompt:**  
In `KeyMinder/Settings/HotkeyManager.swift` (non-sandboxed macOS 14+ app, v0.1.79), inside `installCarbonHandler`, find:

```swift
if hkID.id == HotkeyManager.eventID {
```

Replace with:

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

### [PC-006] — `NSApp.activate(ignoringOtherApps:)` deprecated in macOS 14

**Severity:** Polish  
**Dimension:** Swift/SwiftUI best practices  
**File(s):** `KeyMinder/AppDelegate.swift` (~line 269), `KeyMinder/UI/Settings/SettingsView.swift` (~line 20)  
**Model:** Sonnet  

**Context:**  
`NSApplication.activate(ignoringOtherApps:)` was deprecated in macOS 14.0; the replacement is `NSApp.activate()` (no argument). The project's deployment target is macOS 14.0 so the modern API is always available. Two call sites exist: `AppDelegate.showAbout()` and `SettingsWindowController.show()`. The build currently reports 0 deprecation warnings (the warning may be suppressed by the SDK or grep filter), but the call should be updated to align with the deployment target.

**Prompt:**  
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.79), replace all uses of `NSApp.activate(ignoringOtherApps: true)` with `NSApp.activate()`.

Two call sites:
1. `KeyMinder/AppDelegate.swift` in `showAbout()` (~line 269).
2. `KeyMinder/UI/Settings/SettingsView.swift` in `SettingsWindowController.show()` (~line 20).

In each file, replace:
```swift
NSApp.activate(ignoringOtherApps: true)
```
with:
```swift
NSApp.activate()
```

Build and confirm 0 warnings:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | \
  grep -E "(warning:|error:|SUCCEEDED|FAILED)"
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-007] — Redundant AX `children()` call when logging empty submenus

**Severity:** Polish  
**Dimension:** Performance  
**File(s):** `KeyMinder/Scraping/MenuScraper.swift` — `collectGroups` (~line 91), `collectShortcutsFlat` (~line 136)  
**Model:** Sonnet  

**Context:**  
When a submenu yields zero shortcuts, both `collectGroups` and `collectShortcutsFlat` call `children(submenu)` a second time just to get the raw child count for the diagnostic log. `children(submenu)` makes a synchronous AX IPC call (up to 1 s each, capped by `AXUIElementSetMessagingTimeout`). The result from the first call could be threaded through by changing `collectShortcutsFlat`'s return type to `(shortcuts: [Shortcut], rawChildCount: Int)`, eliminating the redundant round-trip for every empty or lazy-populated submenu.

**Prompt:**  
In `KeyMinder/Scraping/MenuScraper.swift` (non-sandboxed macOS 14+ app, v0.1.79), eliminate the redundant second `children(submenu)` call when logging empty submenus.

**Change 1 — `collectShortcutsFlat` signature.**

Change return type from `[Shortcut]` to `(shortcuts: [Shortcut], rawChildCount: Int)`. At the top of the function body, store children once:
```swift
let menuChildren = children(menu)
```
Iterate `menuChildren` instead of calling `children(menu)`. Change the early-return at `depth >= 10` to `return ([], 0)`. Change `return result` at the end to `return (result, menuChildren.count)`.

**Change 2 — Update call site in `collectGroups`.**

```swift
// Before:
let submenuItems = collectShortcutsFlat(in: submenu, includeAll: includeAll, ignoredTitles: ignoredTitles)
if !submenuItems.isEmpty {
    named.append(ShortcutGroup(title: title, shortcuts: submenuItems))
} else {
    let itemCount = children(submenu).count   // ← redundant AX call
    let hint = itemCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
// After:
let (submenuItems, rawChildCount) = collectShortcutsFlat(in: submenu, includeAll: includeAll, ignoredTitles: ignoredTitles)
if !submenuItems.isEmpty {
    named.append(ShortcutGroup(title: title, shortcuts: submenuItems))
} else {
    let hint = rawChildCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
```

**Change 3 — Update recursive call site inside `collectShortcutsFlat`.**

```swift
// Before:
let sub = collectShortcutsFlat(in: submenu, includeAll: includeAll, depth: depth + 1, ignoredTitles: ignoredTitles)
if sub.isEmpty {
    let itemCount = children(submenu).count   // ← redundant AX call
    let hint = itemCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
result.append(contentsOf: sub)
// After:
let (sub, subChildCount) = collectShortcutsFlat(in: submenu, includeAll: includeAll, depth: depth + 1, ignoredTitles: ignoredTitles)
if sub.isEmpty {
    let hint = subChildCount == 0 ? "; likely lazy-populated" : ""
    Logger.scraper.info(...)
}
result.append(contentsOf: sub)
```

Build and run all tests:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | \
  grep -E "(warning:|error:|PASSED|FAILED)"
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-008] — `SettingsWindowController.init()` creates two `SettingsView` instances

**Severity:** Polish  
**Dimension:** Performance  
**File(s):** `KeyMinder/UI/Settings/SettingsView.swift` — `SettingsWindowController.init()` (~line 24)  
**Model:** Sonnet  

**Context:**  
`SettingsWindowController.init()` constructs a throwaway `NSHostingController(rootView: SettingsView())` solely to measure the natural content height, then immediately constructs a second `NSHostingView(rootView: SettingsView())` for actual display. Each `SettingsView()` construction initialises a `SettingsModel`, which reads `UserDefaults` and calls `LoginItemManager.shared.isEnabled` (an `SMAppService` query). The measurement controller is discarded after `.sizeThatFits` returns. `NSHostingController.view` is the backing `NSView` of the controller — it can be assigned directly as the window's `contentView`, so the controller can serve both purposes.

**Prompt:**  
In `KeyMinder/UI/Settings/SettingsView.swift` (non-sandboxed macOS 14+ app, v0.1.79), refactor `SettingsWindowController.init()` to create only one `SettingsView()` instance.

Replace:
```swift
private init() {
    let measured = NSHostingController(rootView: SettingsView())
        .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
        .height.rounded()
    let contentHeight = min(max(measured, 300), 700)

    let hosting = NSHostingView(rootView: SettingsView())
    ...
}
```

With:
```swift
private init() {
    let controller = NSHostingController(rootView: SettingsView())
    let measured = controller
        .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
        .height.rounded()
    let contentHeight = min(max(measured, 300), 700)

    let hosting = controller.view
    ...
}
```

All remaining code in `init` is unchanged. Build and confirm BUILD SUCCEEDED:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build 2>&1 | tail -5
```
Open Settings from the right-click context menu and confirm the window appears and all tabs, toggles, and fields work correctly. Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-009] — `MenuSectionView.isShown` reads `UserDefaults` directly instead of accepting a prop

**Severity:** Polish  
**Dimension:** Architecture  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift` — `MenuSectionView` (~line 462), `FilterableShortcutsView.grid` (~line 296)  
**Model:** Sonnet  

**Context:**  
`MenuSectionView.isShown(_:)` reads `UserDefaults.standard.showDeactivatedSystemShortcuts` directly inside a SwiftUI computed property. `UserDefaults` is not `@Observable`, so a runtime change to this key cannot trigger a SwiftUI re-render. Every other filter flag (`query`, `showsAllItems`, `modifierFilter`, `showOnlyFavourites`, `dimMode`) is explicitly passed as a named prop from the parent, making `MenuSectionView`'s inputs auditable. The `showDeactivatedSystemShortcuts` read bypasses that contract, creating a hidden dependency. In the current flow there is no observable bug (the popup is always re-created after the setting changes), but the inconsistency will become a correctness bug if popup and Settings are ever allowed to coexist.

**Prompt:**  
In `KeyMinder/UI/Popup/PopupRootView.swift` (non-sandboxed macOS 14+ app, v0.1.79), replace the direct `UserDefaults` read in `MenuSectionView.isShown` with an explicit prop.

**Step 1 — Add prop to `MenuSectionView`.**  
Add the following alongside the other filter props (e.g. after `var dimMode: Bool = false`):
```swift
var showDeactivatedSystemShortcuts: Bool = false
```

**Step 2 — Update `isShown` to use the prop.**  
Change the guard inside `if shortcut.isDisabled {`:
```swift
// Before:
guard UserDefaults.standard.showDeactivatedSystemShortcuts else { return false }
// After:
guard showDeactivatedSystemShortcuts else { return false }
```

**Step 3 — Thread the value through `FilterableShortcutsView.grid`.**  
In the `MenuSectionView(...)` call site inside `grid` (~line 299), add the new argument:
```swift
showDeactivatedSystemShortcuts: UserDefaults.standard.showDeactivatedSystemShortcuts,
```
(Reading UserDefaults at the view boundary in the parent is acceptable; SwiftUI rebuilds `FilterableShortcutsView` when its `@Bindable` model changes, and the popup is always re-created fresh after the setting changes.)

No other changes. Build and run all tests:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | tail -5
```
Bump `MARKETING_VERSION` and tag. Build to `/tmp`.

---

### [PC-010] — `PopupController.measuredContent` creates two `PopupFilterModel` instances

**Severity:** Polish  
**Dimension:** Performance  
**File(s):** `KeyMinder/UI/Popup/PopupController.swift` — `measuredContent` (~line 285), `KeyMinder/UI/Popup/PopupRootView.swift` — `PopupFilterModel` (~line 82)  
**Model:** Sonnet  

**Context:**  
`measuredContent` creates a `placeholderModel` with `fitsWithoutScrolling: false` for the height-measurement pass, then constructs a second `model` with the correct `fitsWithoutScrolling` value for the live display. Each `PopupFilterModel.init` calls `updateVisibleShortcuts()`, which queries `IgnoreListStore.shared.ignoredTitles(for:)` (building a `Set<String>`) and iterates every shortcut. The placeholder is discarded immediately. Since `fitsWithoutScrolling` is not used inside `updateVisibleShortcuts()` — it only controls `dimMode` in `MenuSectionView` — the placeholder model can be reused as the live model by changing `fitsWithoutScrolling` from `let` to `var` and setting it after the measurement.

**Prompt:**  
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.79), eliminate the redundant `PopupFilterModel` in `measuredContent`.

**Change 1 — `PopupFilterModel.fitsWithoutScrolling`.**  
In `KeyMinder/UI/Popup/PopupRootView.swift`, in `PopupFilterModel`, change:
```swift
let fitsWithoutScrolling: Bool
```
to:
```swift
var fitsWithoutScrolling: Bool
```

**Change 2 — `PopupController.measuredContent`.**  
In `KeyMinder/UI/Popup/PopupController.swift`, replace the section that creates `placeholderModel` and `model` (~lines 285–305):

```swift
// Before:
let placeholderModel = PopupFilterModel(app: app, columns: displayColumns)
let measureView = rootView(content, model: placeholderModel, width: width, height: nil, scrolls: false)
let measurer = NSHostingController(rootView: measureView)
let naturalHeight = measurer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
let height = min(naturalHeight, maxPanelHeight)

let fitsWithoutScrolling = naturalHeight <= maxPanelHeight
let model = PopupFilterModel(app: app, columns: displayColumns, fitsWithoutScrolling: fitsWithoutScrolling)
if let bid = app.bundleIdentifier, bid == lastFilterBundleID { model.query = lastFilterQuery }
model.heldModifiers = Self.extractModifiers(from: NSEvent.modifierFlags)
filterModel = model

// After:
let model = PopupFilterModel(app: app, columns: displayColumns)  // fitsWithoutScrolling defaults false
let measureView = rootView(content, model: model, width: width, height: nil, scrolls: false)
let measurer = NSHostingController(rootView: measureView)
let naturalHeight = measurer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
let height = min(naturalHeight, maxPanelHeight)

model.fitsWithoutScrolling = naturalHeight <= maxPanelHeight   // update in place
if let bid = app.bundleIdentifier, bid == lastFilterBundleID { model.query = lastFilterQuery }
model.heldModifiers = Self.extractModifiers(from: NSEvent.modifierFlags)
filterModel = model
```

All remaining code in `measuredContent` (building `root` and returning) is unchanged.

Build and run all tests:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
  -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test 2>&1 | \
  grep -E "(PASSED|FAILED|error:)"
```
Open the popup against a real app and confirm the layout and dim-mode behaviour are unchanged. Bump `MARKETING_VERSION` and tag. Build to `/tmp`.
