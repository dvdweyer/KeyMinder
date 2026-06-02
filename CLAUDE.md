# KeyMinder

macOS menu-bar app that pops up the **active keyboard shortcuts of the frontmost
app**, grouped by menu. SwiftUI + AppKit, **macOS 14+**, full
Xcode project. Reads other apps' menus via the Accessibility API.

## Build & run

- **In Xcode:** open `KeyMinder.xcodeproj`, Run (⌘R). Xcode builds into
  `~/Library/Developer/Xcode/DerivedData` (outside iCloud), which avoids the
  codesign issue below.
- **CLI build:**
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
    -derivedDataPath /tmp/KeyMinder-build -allowProvisioningUpdates build
  ```
  - `DEVELOPER_DIR` is required because the active developer dir is Command Line
    Tools, not full Xcode.
  - **Never build into the project folder.** It lives in an iCloud-synced
    `~/Documents`, which stamps build products with `com.apple.FinderInfo` /
    `com.apple.fileprovider` xattrs that make `codesign` fail with "resource
    fork, Finder information, or similar detritus not allowed". Build to `/tmp`
    or default DerivedData.

## Install for testing (Accessibility)

KeyMinder needs **Accessibility permission** to read other apps' menus. macOS TCC
will **not register an app run from `/tmp` or DerivedData** into the Accessibility
list — it must run from a stable location:

```
cp -R /tmp/KeyMinder-build/Build/Products/Debug/KeyMinder.app /Applications/
xattr -cr /Applications/KeyMinder.app
open /Applications/KeyMinder.app
```

Signed with an **Apple Development** cert (team `R4J8ZNC9HF`), so the grant is
identity-based and **persists across rebuilds and run locations**. Reset with
`tccutil reset Accessibility org.afaik.KeyMinder`.

## Distribution

- **TestFlight / Mac App Store are impossible for this app.** App Store Connect
  requires the **App Sandbox**, and a sandboxed process **cannot use the
  Accessibility API to read other apps** — no entitlement (including
  temporary-exception ones) re-opens this. The TCC Accessibility grant does
  **not** punch through the sandbox; they are separate layers. This is the same
  wall that keeps KeyCue, Shortcat, Bartender, etc. off the Mac App Store.
- **The shipping path is Developer ID + notarization:** Archive → Distribute App
  → **Direct Distribution** → notarize → staple → zip/DMG to users.
- Release config already has **Hardened Runtime on** (required for notarization).
  There is **no entitlements file**, so the app is non-sandboxed — correct for
  this path. For a distribution archive, switch the signing identity from
  "Apple Development" to **"Developer ID Application"** (Xcode automatic signing
  does this when you pick Direct Distribution).

## Logs

```
/usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder'"
```
Use the **full path** `/usr/bin/log` (a shell function shadows `log`). `info`
level is hidden unless you pass `--level info`.

## Architecture

### App entry point

- `KeyMinderApp.swift` — `@main`; empty `Settings` scene. All UI is driven by `AppDelegate`.
- `AppDelegate.swift` (`@MainActor`) — owns the `NSStatusItem` (left-click toggles
  the popup, right-click shows context menu), `FrontmostAppMonitor`, and
  `PopupController`. `presentPopup()` runs an async scrape via two stored tasks:
  `scrapeTask` (outer coordinator) and `detachedScrapeTask` (background `Task.detached`
  AX work); both are cancelled before each new scrape to prevent concurrent traversals.
  On first launch, `setupHotkey()` seeds ⌥⌘K as the factory default hotkey (guarded by
  `didSetDefaultHotkey` so the seed runs only once and never overwrites a deliberate
  "no hotkey" choice). The right-click context menu shows a disabled info row with the
  current hotkey (or "(unset)") so users can discover their trigger without opening
  Settings; it also has Settings…, About KeyMinder, and Quit. `onPermissionGranted`
  calls `setupDoubleTap()` then `presentPopup()` so the double-tap trigger is armed
  the moment Accessibility is granted without requiring a relaunch.
  `setupSleepWakeObserver()` re-arms the trigger on `NSWorkspace.didWakeNotification`
  (sleep/wake can invalidate event monitors). `showWelcomePopupIfNeeded()` auto-presents
  the popup 500 ms after first launch so the user discovers the app immediately.
  `showAbout()` calls `NSApp.orderFrontStandardAboutPanel` with the version and an
  attributed-string credits block linking to the homepage.

### Monitoring & Accessibility

- `Monitoring/FrontmostAppMonitor.swift` — tracks the frontmost app via
  `NSWorkspace` notifications, ignoring KeyMinder itself.
- `Accessibility/AccessibilityPermission.swift` — trust check / prompt / open Settings.
- `Accessibility/ShortcutActivator.swift` — calls `AXUIElementPerformAction(kAXPressAction)` on a
  shortcut's stored `axElement` to run the menu item in the target app; used when the user clicks
  a row in the popup.

### Scraping

- `Scraping/MenuScraper.swift` — AX traversal of the menu bar → `[MenuSection]`.
  Each top-level menu produces one unnamed `ShortcutGroup` for its direct items plus
  one named `ShortcutGroup` per submenu (title = submenu name). Sub-submenus (depth ≥ 2)
  are flattened into their parent's named group. Accepts `includeItemsWithoutShortcuts`
  to emit leaf items with no key equivalent (empty `keys` string) for all-entries mode.
  Caps per-request AX timeouts at 1 s via `AXUIElementSetMessagingTimeout`.
- `Scraping/ShortcutFormatter.swift` — decodes the AX modifier mask
  (shift=1, option=2, control=4, no-command=8) plus char/glyph/virtual-key into
  display symbols (⌃⌥⇧⌘ + key).

### Model

- `Model/ShortcutModel.swift` — `Shortcut` (title + keys string + optional
  `AXUIElement`); `ShortcutGroup` (`title == nil` for a menu's direct items, non-nil
  for a named submenu group); `MenuSection` (one top-level menu → one unnamed group +
  zero or more named submenu groups); `AppShortcuts` (all sections for one app, plus
  `includesItemsWithoutShortcuts` flag); `PopupContent` enum. Matching extensions on
  all types; `Shortcut.matches(_:)` is case- and diacritic-insensitive via
  `localizedStandardContains` and explicitly returns `true` for an empty query.
  `Shortcut.modifiers` extracts the set of modifier glyphs (⌃⌥⇧⌘) present in `keys`;
  `matchesModifierFilter(_:)` returns `true` when the filter set is empty or exactly
  equals `modifiers` (exact-match semantics — ⌘ matches only ⌘X, not ⇧⌘X).

### Settings

- `Settings/HotkeyManager.swift` (`@MainActor`) — singleton; registers a global
  hotkey via Carbon `RegisterEventHotKey`. The C event-handler callback dispatches
  to the main actor via `DispatchQueue.main.async`.
- `Settings/GlobalHotkey.swift` — value type encoding a key code + Carbon modifier
  mask; `UserDefaults` persistence; `displayString` for UI. `defaultHotkey` (⌥⌘K) is
  the factory default applied on first launch; `didSetDefaultHotkey` flag in
  `UserDefaults` ensures the seed runs exactly once.
- `Settings/DoubleTapTrigger.swift` — detects a rapid double-press of a single
  modifier key using `NSEvent.addGlobalMonitorForEvents` (`.flagsChanged` + `.keyDown`).
  Runs entirely on the main thread; no CGEventTap, no background thread. The
  `DoubleTapModifier` enum maps each key to its `NSEvent.ModifierFlags` bit via
  `nsFlag`. State machine: `idle → firstDown → firstUp → FIRED` with a 500 ms window.
  `start(modifier:)` / `stop()` install and remove the monitors; called from
  `AppDelegate.setupDoubleTap()` on launch, on Accessibility grant, and on wake.
  All `.debug()` log calls are gated behind `UserDefaults.standard.debugLoggingEnabled`
  (default `false`); see `Support/Logging.swift` for the UserDefaults extension.
- `Settings/LoginItemManager.swift` — wraps `SMAppService` to register/unregister
  the app as a login item.

### UI — Popup

- `UI/Popup/PopupController.swift` (`@MainActor`) — NSPanel lifecycle: `show()` /
  `hide()` with fade-in (0.12 s) and scale (0.98→1.0) / fade-out (0.10 s) animations;
  dismissal monitors (click-outside, Esc, app-switch). `activeVisibleFrame` selects the
  screen containing the mouse cursor (primary), then `NSScreen.main`, then the first
  screen — nil-safe to survive display-reconfiguration races. The panel is always
  centered on that screen. Esc clears a non-empty text filter, then the toggled modifier
  filter, then dismisses. A local key monitor handles Tab (advance row selection) /
  Shift-Tab (reverse) / Return or numpad Enter (activate selected shortcut). Permission-
  poll timer fires `onPermissionGranted` the moment `AXIsProcessTrusted()` becomes true.
  Panel is released (`self.panel = nil`) on hide to free the SwiftUI tree while idle.
  Two `flagsChanged` event monitors (global for when another app is frontmost, local for
  when the popup panel is key) call `handleFlagsChanged(_:)` which writes the currently
  held modifier glyphs to `filterModel.heldModifiers` via `extractModifiers(from:)`.
  On popup open, `NSEvent.modifierFlags` seeds `heldModifiers` so the filter is
  immediately correct if modifier keys are already held. `measuredContent` computes
  `fitsWithoutScrolling = naturalHeight ≤ maxPanelHeight` and passes it to the model.
- `UI/Popup/PopupPanel.swift` — non-activating `NSPanel` subclass.
- `UI/Popup/PopupRootView.swift` — contains all popup SwiftUI types:
  - `PopupFilterModel` (`@Observable @MainActor`) — owned by `PopupController`;
    holds the live `query`, fixed `columns` layout, `selectedIndex` for Tab navigation,
    cached `visibleShortcuts` (recomputed on each query/modifier change), `displayableCount`,
    `matchCount`, and `showsAllItems` (true when all-entries mode is on and query ≥ 2
    chars). `selectNext()` / `selectPrevious()` wrap around. Modifier filtering uses two
    backing stores: `toggledModifiers` (persistent, driven by UI button clicks via
    `toggleModifier(_:)` / `clearToggledModifiers()`) and `heldModifiers` (ephemeral,
    driven by physical key state set by `PopupController`). The computed `modifierFilter`
    is their union and is used for all filtering. `hasToggledModifiers` lets the Esc
    handler clear only persistent state (held keys self-clear on release).
    `fitsWithoutScrolling` (set once at init by the controller) switches `MenuSectionView`
    into dim mode when true.
  - `PopupRootView` — dispatches to `FilterableShortcutsView`, `PopupOnboardingView`,
    or `PopupMessageView`; applies `.regularMaterial` background + border overlay.
  - `FilterableShortcutsView` — header (app icon, name, count, modifier toggle buttons,
    auto-focused search field) + scrollable shortcut grid; auto-focuses the filter field
    on appear; scroll-follows the selected row. Modifier buttons (⌃ ⌥ ⇧ ⌘) are rendered
    by `ModifierToggle` — filled with `Theme.keyAccent` when active, outlined when not.
  - `MenuSectionView` — one section card: section header (`.isHeader` VoiceOver trait)
    + optional `SubGroupHeader` labels for named submenu groups + shortcut rows. In normal
    mode the card is absent when no rows pass the filter. In dim mode (`dimMode: true`)
    every keyed row is always rendered; non-matching rows are passed `dimmed: true` and
    only empty sections (no keyed shortcuts at all) are hidden. Section and sub-group
    headers always stay at full opacity in dim mode.
  - `SubGroupHeader` — compact label above a submenu's items inside a section card.
  - `ShortcutRow` — right-aligned key glyphs + command title; hover highlight and
    tap-to-activate when the row has an `axElement`; VoiceOver label via `spokenKeys(_:)`
    (e.g. "⇧⌘N" → "Shift Command N"); Tab-selection highlight. When `dimmed: true` both
    text elements use `Theme.fadedText`, `clickable` is false (no tap, no hover, no
    `.isButton` trait), and the row is invisible to Tab navigation (it is absent from
    `visibleShortcuts`).
  - `PopupMessageView` — centered icon-over-text placeholder for empty / no-app states.
- `UI/Popup/MenuLayout.swift` — layout constants (`columnWidth`, `columnSpacing`,
  `sectionSpacing`, `rowHeight`, `rowSpacing`, `headerHeight`, `subGroupHeaderHeight`)
  and two algorithms: `height(of:)` estimates a section card's rendered height
  (accounting for sub-group headers); `distribute(_:columns:)` partitions sections
  into at most `columns` contiguous slices using binary search on per-column capacity
  to minimise the tallest column.
- `UI/Popup/Theme.swift` — colours, spacing constants. `fadedText` is the low-contrast
  colour used for dimmed rows in dim mode (light grey / dark grey adaptive).
- `UI/Popup/PopupOnboardingView.swift` — onboarding screen shown before Accessibility
  is granted.

### UI — Settings

- `UI/Settings/SettingsView.swift` — contains three types:
  - `SettingsWindowController` (`@MainActor NSWindowController`) — singleton that
    measures the natural content height via `NSHostingView.fittingSize` at width 420
    before creating the `NSWindow`, so the window always fits its content (including
    at larger accessibility text sizes).
  - `SettingsModel` (`@MainActor @Observable`) — hotkey recording state, UserDefaults
    persistence, `HotkeyManager` registration, login-item toggle, double-tap config
    (`doubleTapEnabled` + `doubleTapModifier`), `showAllMenuItems` (popup content mode),
    and `debugLoggingEnabled` toggle (all persisted to `UserDefaults`).
  - `SettingsView` — five sections: Global Shortcut (hotkey badge + record/change/clear),
    Launch at Login toggle, Double-tap Trigger (enable toggle + modifier picker), Popup
    Content ("Show all menu entries" toggle), Developer (debug logging toggle).
  - `HotkeyBadge` — pill badge showing current hotkey or recording prompt; `@State`
    owns `SettingsModel`.

### Assets & support

- `Assets.xcassets/` — `AppIcon.appiconset` (10 PNG slots, 16 pt → 512 pt @1×/@2×)
  and `AccentColor.colorset` (system accent colour).
- `Support/Logging.swift` — `os.Logger` subsystem/category constants.

### Tests

- `KeyMinderTests/MenuLayoutTests.swift` — `MenuLayout.height(of:)` and
  `MenuLayout.distribute(_:columns:)`.
- `KeyMinderTests/ShortcutFormatterTests.swift` — full coverage of
  `ShortcutFormatter.format(cmdChar:virtualKey:glyph:modifiers:)`.
- `KeyMinderTests/ShortcutMatchingTests.swift` — `Shortcut.matches`,
  `ShortcutGroup.hasMatch`, `MenuSection.hasMatch`, `AppShortcuts.matchCount`.
- `KeyMinderTests/DoubleTapTriggerTests.swift` — state machine driven via
  `handleFlags(_:)` (NSEvent monitors do not fire in unit tests); covers happy-path,
  chord reset, expired window, and modifier switch.
- `KeyMinderTests/PopupFilterModelTests.swift` — filter query, `displayableCount`,
  `matchCount`, `showsAllItems`, Tab navigation, modifier filter (exact-match semantics,
  toggled vs held layers, union, `clearToggledModifiers`, `hasToggledModifiers`).

The Xcode project uses a **file-system-synchronized group** (objectVersion 70):
new `.swift` files under `KeyMinder/` are picked up automatically — no need to
edit `project.pbxproj`.

## Conventions

- macOS 14+ (deployment target 14.0); Swift 5 language mode (`SWIFT_VERSION = 5.0`).
  Newest APIs in use all land at 14.0: `@Observable`, `.scrollBounceBehavior`,
  `MainActor.assumeIsolated` — so no `if #available` branching is needed.
- **Observable models use `@Observable`** (Swift Observation, not Combine
  `ObservableObject`). View ownership: `@State` for the owning view, plain `var`
  for child views (observation is automatic), `@Bindable` when `$model.property`
  bindings are needed.
- **Concurrency**: defer work with `Task { }` rather than
  `DispatchQueue.main.async { }`. SwiftUI `.onAppear` closures are `@MainActor`,
  so a plain `Task` inherits that context.
- Light/dark handled automatically via `.regularMaterial` + semantic colors.
- **Versioning: every commit bumps the patch (last) number** of
  `MARKETING_VERSION` and is tagged `vX.Y.Z`. Canonical sources of truth:
  `MARKETING_VERSION` in `KeyMinder.xcodeproj/project.pbxproj`, or
  `git tag --sort=-v:refname | head -1`.

## Known limitations / next up

- AX scraping runs on a background `Task.detached`; the main thread is unblocked, but
  the AX IPC itself is synchronous C code with no Swift cancellation checkpoints — a
  busy target app can still delay the popup until the 1 s AX timeout fires.
- System-wide shortcuts (Spotlight, Screenshots, …) not implemented yet — planned phase.
- **Lazy-populated submenus are invisible to the scraper.** Apps that use
  `NSMenuDelegate`'s `menuNeedsUpdate:` or `menu:updateItem:atIndex:shouldCancel:`
  only fill submenu items when the menu is about to be *displayed*.  The AX
  bridge reads items as-is from the in-memory `NSMenu`; no AX attribute read,
  no re-query of `kAXChildrenAttribute`, and no delay triggers that delegate
  callback.  Known affected cases:
    - **Finder → "Open With"** (fully lazy — 0 AX children until the menu opens).
    - **Any app** whose dynamic submenus (e.g. window lists, recent items) are
      populated on-demand.
  Intrusive workarounds (`kAXPressAction`, `kAXShowMenuAction`, synthetic
  `CGEvent` clicks) would flash menus on screen and are intentionally excluded.
  The scraper now logs these at `.info` as
  `"Submenu '<name>' yielded 0 items (0 child items; likely lazy-populated)"`
  so occurrences can be quantified with:
  ```
  /usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder'"
  ```
