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
  the popup, right-click shows context menu with Settings, About, and Quit), `FrontmostAppMonitor`, and
  `PopupController`. `presentPopup()` runs an async scrape via two stored tasks:
  `scrapeTask` (outer coordinator) and `detachedScrapeTask` (background AX work);
  both are cancelled before each new scrape to prevent concurrent traversals.
  `onPermissionGranted` calls `setupDoubleTap()` then `presentPopup()` so the
  double-tap trigger is armed the moment Accessibility is granted without requiring
  a relaunch. `setupSleepWakeObserver()` re-arms the trigger on
  `NSWorkspace.didWakeNotification` (sleep/wake invalidates event monitors).
  `showAbout()` calls `NSApp.orderFrontStandardAboutPanel` with the version and
  an attributed-string credits block linking to the homepage.

### Monitoring & Accessibility

- `Monitoring/FrontmostAppMonitor.swift` — tracks the frontmost app via
  `NSWorkspace` notifications, ignoring KeyMinder itself.
- `Accessibility/AccessibilityPermission.swift` — trust check / prompt / open Settings.
- `Accessibility/ShortcutActivator.swift` — calls `AXUIElementPerformAction(kAXPressAction)` on a
  shortcut's stored `axElement` to run the menu item in the target app; used when the user clicks
  a row in the popup.

### Scraping

- `Scraping/MenuScraper.swift` — AX traversal of the menu bar → `[MenuSection]`.
  **Submenus are currently flattened** into the parent menu.
- `Scraping/ShortcutFormatter.swift` — decodes the AX modifier mask
  (shift=1, option=2, control=4, no-command=8) plus char/glyph/virtual-key into
  display symbols (⌃⌥⇧⌘ + key).

### Model

- `Model/ShortcutModel.swift` — `Shortcut`, `ShortcutGroup`, `MenuSection`,
  `AppShortcuts`, `PopupContent`. Matching extensions on all types;
  `Shortcut.matches(_:)` is case- and diacritic-insensitive via
  `localizedStandardContains` and explicitly returns `true` for an empty query.

### Settings

- `Settings/HotkeyManager.swift` (`@MainActor`) — singleton; registers a global
  hotkey via Carbon `RegisterEventHotKey`. The C event-handler callback dispatches
  to the main actor via `DispatchQueue.main.async`.
- `Settings/GlobalHotkey.swift` — value type encoding a key code + Carbon modifier
  mask; `UserDefaults` persistence; `displayString` for UI.
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
  `hide()` with fade animations; dismissal monitors (click-outside, Esc, app-switch);
  `activeVisibleFrame` for nil-safe screen geometry (crash-safe during display
  reconfiguration); permission-poll timer that fires `onPermissionGranted` the moment
  `AXIsProcessTrusted()` becomes true; panel is released (`self.panel = nil`) on hide
  to free the SwiftUI tree while the popup is not visible.
- `UI/Popup/PopupPanel.swift` — non-activating `NSPanel` subclass.
- `UI/Popup/PopupRootView.swift` — root SwiftUI view; `PopupFilterModel` (`@Observable
  @MainActor`) holds the live filter query owned by `PopupController`; `PopupRootView`
  dispatches to `FilterableShortcutsView` (shortcuts grid with type-to-filter),
  `PopupOnboardingView`, or `PopupMessageView`.
- `UI/Popup/MenuLayout.swift` — greedy column-balancing algorithm (binary search on
  capacity); `MenuSectionView` / `ShortcutRow` with full VoiceOver support
  (`.isHeader` trait on section titles; composed spoken labels on shortcut rows via
  `spokenKeys(_:)`; decorative images hidden).
- `UI/Popup/Theme.swift` — colours, spacing constants.
- `UI/Popup/PopupOnboardingView.swift` — onboarding screen shown before Accessibility
  is granted.

### UI — Settings

- `UI/Settings/SettingsView.swift` — contains three types:
  - `SettingsWindowController` (`@MainActor NSWindowController`) — singleton that
    measures the natural content height via `NSHostingView.fittingSize` at width 420
    before creating the `NSWindow`, so the window always fits its content (including
    at larger accessibility text sizes).
  - `SettingsModel` (`@MainActor @Observable`) — hotkey recording state, UserDefaults
    persistence, `HotkeyManager` registration, login-item toggle, double-tap config,
    and `debugLoggingEnabled` toggle (writes to `UserDefaults`).
  - `SettingsView` / `HotkeyBadge` — SwiftUI views; `@State` owns `SettingsModel`.

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

- Submenu sub-group headers (e.g. "Move & Resize") not shown yet — scraper flattens submenus.
- AX scraping runs on the main thread; a busy target app could briefly block.
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
  `"Submenu '<name>' yielded 0 shortcuts (0 child items; likely lazy-populated)"`
  so occurrences can be quantified with:
  ```
  /usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder'"
  ```
