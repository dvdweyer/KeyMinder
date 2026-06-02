# App Review — 2026-06-02

## Summary

KeyMinder v0.1.49 is a clean, well-structured macOS 14+ menu-bar utility that reads any frontmost app's AX menu tree and displays keyboard shortcuts in a fast, type-to-filter popup. The architecture is sound (`@MainActor`-isolated controllers, cancellable async scrape, proper `@Observable` models), and the build is warning-free. The most important finding this cycle is a **test-suite compile failure** caused by a missing required parameter in the `AppShortcuts` test fixture — meaning no unit tests have been runnable since the `includesItemsWithoutShortcuts` field was added. One carry-over from `Security_Fixes_2026-06-01.md` (the force-cast in `MenuScraper`) remains unapplied. The remaining findings are low-severity: a misleading onboarding string, a redundant computation in `PopupFilterModel`, and missing test coverage for newer logic paths.

---

## Build & Runtime Notes

| | |
|---|---|
| Build result | ✅ **BUILD SUCCEEDED** — 0 warnings, 0 errors |
| Test result | ❌ **TEST FAILED** — compile error in `KeyMinderTests/ShortcutMatchingTests.swift:26` |
| Xcode SDK | macOS 26 (target arm64-apple-macos14.0) |
| Swift version | 5.0 |
| Version | 0.1.49 |

**Test failure detail:**

```
KeyMinderTests/ShortcutMatchingTests.swift:26:94: error: missing argument for parameter
'includesItemsWithoutShortcuts' in call
```

`AppShortcuts.init` requires `includesItemsWithoutShortcuts: Bool` (added when the
all-entries mode feature was shipped), but the test-only `AppShortcuts.fixture` factory in
`ShortcutMatchingTests.swift` still calls the old three-parameter form. The entire test
suite fails to compile.

**Security carry-over:** `MenuScraper.element(_:_:)` (line 154) still uses `as!` after a
type-ID guard. Fix 1 from `Security_Fixes_2026-06-01.md` was never applied; all other
fixes in that document were applied correctly.

---

## Proposed Changes

### [PC-001] — Fix test-suite compile failure: missing `includesItemsWithoutShortcuts` in fixture

**Severity:** High  
**Dimension:** Test coverage / Correctness  
**File(s):** `KeyMinderTests/ShortcutMatchingTests.swift:26`  
**Model:** Sonnet  

**Context:**  
`AppShortcuts` gained a required `includesItemsWithoutShortcuts: Bool` parameter when the
all-entries mode was added. The test-only `AppShortcuts.fixture` factory in
`ShortcutMatchingTests.swift` still passes the old three arguments, causing a compile error
that prevents any test in the suite from running. All `AppShortcutsMatchCount` tests —
currently the only coverage for `AppShortcuts.matchCount` — have been silently broken since
that feature shipped.

**Prompt:**  
```
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.49), fix the test-suite compile failure
in KeyMinderTests/ShortcutMatchingTests.swift.

The private extension on AppShortcuts at the top of that file defines:

    private extension AppShortcuts {
        static func fixture(sections: [MenuSection]) -> AppShortcuts {
            AppShortcuts(appName: "TestApp", bundleIdentifier: nil, icon: nil, sections: sections)
        }
    }

AppShortcuts.init now requires a fifth argument `includesItemsWithoutShortcuts: Bool`.
Add `includesItemsWithoutShortcuts: false` to the AppShortcuts call inside the fixture so
it compiles.

After the fix, run the tests:
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
      -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
      -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test

All tests must pass. Bump the patch version in project.pbxproj and tag vX.Y.Z per
CLAUDE.md conventions. Build to /tmp (never into the iCloud project folder).
```

---

### [PC-002] — Replace force-cast with conditional cast in `MenuScraper.element(_:_:)`

**Severity:** Medium  
**Dimension:** Correctness  
**File(s):** `KeyMinder/Scraping/MenuScraper.swift:154`  
**Model:** Sonnet  

**Context:**  
`MenuScraper.element(_:_:)` (line 154) returns with `return (raw as! AXUIElement)` after
a `CFGetTypeID` guard. The guard makes the crash impossible under normal AX behaviour, but
if the AX runtime ever returns an unexpected type (corrupt attribute, future API change)
the force cast crashes KeyMinder rather than returning `nil`. The return type is already
`AXUIElement?` and all callers handle `nil`. This is Fix 1 from
`Security_Fixes_2026-06-01.md`, documented on 2026-06-01, still unapplied.

**Prompt:**  
```
In KeyMinder/Scraping/MenuScraper.swift (non-sandboxed macOS 14+ app, v0.1.49), find the
private static method `element(_:_:)`. It currently ends with:

    return (raw as! AXUIElement)

Replace the force cast with a conditional cast:

    return raw as? AXUIElement

The surrounding guard (`CFGetTypeID(raw) == AXUIElementGetTypeID()`), the return type
(AXUIElement?), and all other code must remain unchanged. Run the tests after the change
to confirm nothing regressed. Bump the patch version and tag vX.Y.Z per CLAUDE.md.
Build to /tmp (never into the iCloud project folder).
```

---

### [PC-003] — Fix misleading onboarding text: "reopen this popup" vs auto-refresh

**Severity:** Low  
**Dimension:** Usability & Accessibility  
**File(s):** `KeyMinder/UI/Popup/PopupOnboardingView.swift:17–20`  
**Model:** Sonnet  

**Context:**  
The onboarding view tells users to grant access "then reopen this popup." But since
v0.1.45, `PopupController` runs a 0.5 s poll that automatically refreshes the popup the
moment `AXIsProcessTrusted()` returns `true` — no reopen is needed. A user who follows the
instruction literally (dismissing the popup before granting access) will see it work, but a
user who keeps the popup open while granting access will see it auto-update and may be
confused by the stale instruction. The text should describe the actual behaviour: the
popup updates automatically.

**Prompt:**  
```
In KeyMinder/UI/Popup/PopupOnboardingView.swift (non-sandboxed macOS 14+ app, v0.1.49),
update the explanatory Text view (lines 17–20) to reflect that the popup refreshes
automatically when Accessibility permission is granted — users do not need to reopen it.

Current text:
    "KeyMinder reads the active app's menus to show its keyboard "
    + "shortcuts. Grant access in Privacy & Security, then reopen this popup."

Replace with:
    "KeyMinder reads the active app's menus to show its keyboard shortcuts. "
    + "Grant access in Privacy & Security — the popup will update automatically."

No other changes. Build, run, and confirm the onboarding screen shows the new text.
Bump the patch version and tag vX.Y.Z per CLAUDE.md.
Build to /tmp (never into the iCloud project folder).
```

---

### [PC-004] — Cache `visibleShortcuts` to avoid redundant traversals on Tab navigation

**Severity:** Low  
**Dimension:** Performance  
**File(s):** `KeyMinder/UI/Popup/PopupRootView.swift:26–39` (`PopupFilterModel.visibleShortcuts`)  
**Model:** Sonnet  

**Context:**  
`PopupFilterModel.visibleShortcuts` is a computed property that iterates the full
`columns → sections → groups → shortcuts` tree on every read. During Tab navigation
`selectNext()` reads it once (for `.count`) and the `ScrollView.onChange(of: selectedIndex)`
immediately reads it again via `selectedShortcut` — two full traversals per Tab press.
For apps with large menus (100+ shortcuts across many columns) this is noticeably slow and
becomes the bottleneck in rapid Tab cycling. The property is a pure function of `query`,
`columns`, `app.includesItemsWithoutShortcuts`, and `selectedIndex` — making it an ideal
candidate for lazy caching via `@Observable`'s fine-grained dependency tracking.

**Prompt:**  
```
In KeyMinder/UI/Popup/PopupRootView.swift (non-sandboxed macOS 14+ app, v0.1.49), optimise
PopupFilterModel so `visibleShortcuts` is computed at most once per unique (query, showsAllItems)
pair, not once per call site.

The class is @MainActor @Observable. The simplest approach:

1. Add a private stored property `_visibleShortcuts: [Shortcut] = []`.
2. Mark `visibleShortcuts` as a stored var (backed by `_visibleShortcuts`): remove the
   computed implementation.
3. Add an `updateVisibleShortcuts()` helper that recomputes and stores the result using
   the existing traversal logic.
4. Call `updateVisibleShortcuts()` from:
   - `init(app:columns:)` (initial state)
   - The `didSet` on `query` (already runs when query changes)
   - After setting `selectedIndex` in `selectNext()` and `selectPrevious()`, you do NOT
     need to recompute — selectedIndex change does not change the visible set.

Important: `showsAllItems` depends on `query`, so it will be up to date whenever
`updateVisibleShortcuts()` is called from the query didSet. Verify that `selectNext`,
`selectPrevious`, and `selectedShortcut` all continue to use the cached array.

Do not change any callers outside PopupFilterModel. Run the tests and confirm they still
pass. Bump the patch version and tag vX.Y.Z per CLAUDE.md.
Build to /tmp (never into the iCloud project folder).
```

---

### [PC-005] — Add `@MainActor` to `FrontmostAppMonitor`

**Severity:** Low  
**Dimension:** Swift/SwiftUI best practices  
**File(s):** `KeyMinder/Monitoring/FrontmostAppMonitor.swift:7`  
**Model:** Sonnet  

**Context:**  
`FrontmostAppMonitor` is `@Observable` but not `@MainActor`-isolated. In practice it is
always used on the main thread: its owner `AppDelegate` is `@MainActor`, the
`NSWorkspace` notification observer uses `queue: .main`, and `frontmostApp` is read only
from `AppDelegate.presentPopup()` (also main actor). Without the annotation the Swift
concurrency checker cannot verify this, and a future reader might not notice the implicit
thread assumption. Adding `@MainActor` makes the constraint explicit, consistent with the
rest of the codebase (`AppDelegate`, `PopupController`, `HotkeyManager`, `DoubleTapTrigger`
all declare `@MainActor`), and future-proofs the class against accidentally off-thread use.

**Prompt:**  
```
In KeyMinder/Monitoring/FrontmostAppMonitor.swift (non-sandboxed macOS 14+ app, v0.1.49),
add `@MainActor` to the class declaration:

    // BEFORE
    @Observable
    final class FrontmostAppMonitor {

    // AFTER
    @MainActor
    @Observable
    final class FrontmostAppMonitor {

The NSWorkspace notification observer already uses `queue: .main`, so the `self?.update(app)`
call inside the observer closure needs `MainActor.assumeIsolated { self?.update(app) }` to
satisfy the compiler — add it there. No other changes.

Run the tests and confirm they pass. Build the project and confirm BUILD SUCCEEDED with
0 warnings. Bump the patch version and tag vX.Y.Z per CLAUDE.md.
Build to /tmp (never into the iCloud project folder).
```

---

### [PC-006] — Add tests for `PopupFilterModel` and `DoubleTapTrigger` state machine

**Severity:** Low  
**Dimension:** Test coverage  
**File(s):** `KeyMinderTests/` (new file)  
**Model:** Sonnet  

**Context:**  
`PopupFilterModel` contains meaningful, non-trivial logic — `visibleShortcuts` (respects
`showsAllItems` threshold, traverses columns), `selectNext`/`selectPrevious` (wrap-around
navigation), `displayableCount`/`matchCount` (all-entries vs shortcuts-only counting) —
none of which has any test coverage. The `DoubleTapTrigger` state machine (`idle →
firstDown → firstUp → FIRED`, chord rejection, time-window expiry) is similarly untested
and has already had one production bug (fixed in v0.1.48). Both modules are pure logic that
can be tested without UI or AX permissions.

**Prompt:**  
```
In KeyMinder (non-sandboxed macOS 14+ app, v0.1.49), add unit tests for two modules that
currently have no coverage:

1. PopupFilterModel (KeyMinderTests/PopupFilterModelTests.swift):
   - Build a fixture AppShortcuts with two sections and several shortcuts (some with empty
     keys, for all-entries mode).
   - Confirm visibleShortcuts returns the right set with an empty query.
   - Confirm visibleShortcuts excludes items with empty keys when showsAllItems is false
     (query.count < 2) and includes them when showsAllItems is true (query.count >= 2) and
     includesItemsWithoutShortcuts is set.
   - Confirm selectNext wraps from last to first, selectPrevious wraps from first to last.
   - Confirm selectedShortcut returns nil when selectedIndex is nil.
   - Confirm matchCount and displayableCount return correct values for a non-empty filter.

2. DoubleTapTrigger state machine (KeyMinderTests/DoubleTapTriggerTests.swift):
   DoubleTapTrigger uses NSEvent global monitors that cannot fire in unit tests. Test only
   the internal handleFlags logic by making the state machine testable: extract the state
   transitions into a package-internal method `handleFlagsForTesting(flags: NSEvent.ModifierFlags)` — or use @testable import and call the existing private `handleFlags(_:)` 
   indirectly. The simplest approach: add an @testable accessor.
   
   Test cases:
   - A valid double-tap sequence (down, up, down within 500 ms) fires onActivate.
   - A chord (two modifiers held simultaneously) resets to idle and does not fire.
   - A double-tap where the second press arrives after 500 ms does not fire.
   - Calling stop() then start() with a new modifier resets state; the old modifier no
     longer triggers.
   
   Do not add real NSEvent monitor calls in tests; only drive the state machine directly.

The Xcode project uses a file-system-synchronized group (objectVersion 70): new .swift
files under KeyMinderTests/ are picked up automatically. Run the full test suite after
adding the new tests:
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
      -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
      -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates test

All tests (existing + new) must pass. Bump the patch version and tag vX.Y.Z per CLAUDE.md.
Build to /tmp (never into the iCloud project folder).
```
