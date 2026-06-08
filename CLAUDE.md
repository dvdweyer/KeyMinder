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
- **The shipping path is Developer ID + notarization.** `scripts/release.sh`
  automates the full pipeline: archive → export (Developer ID) → notarize →
  staple → re-zip → update Sparkle appcast → copy to local site dirs → rsync
  deploy. Run it from the repo root; it reads `TEAM_ID` from `scripts/.env`
  (not checked in) and the notarytool keychain profile `KeyMinder` (set up once
  via `scripts/setup-notarytool.sh`). `generate_appcast` must be on `PATH`
  (install once via `scripts/setup-sparkle-tools.sh`).
  - **No flags (interactive)**: prompts to choose a pipeline.
  - **`--remote-only`**: Release build → notarize → rsync. No local install.
  - **`--full-deploy`**: Same as `--remote-only`, then installs to `/Applications`.
  - **`--local-only`**: Debug build → install to `/Applications` only. Skips
    `.env`, version checks, notarization, and rsync. Use for rapid local testing.
- **Sparkle auto-updater** (v0.1.84+): `Distribution/appcast.xml` is the feed
  served at `https://keyminder.app/appcast.xml`. Each release run regenerates it
  via `generate_appcast`. The Ed25519 private key lives in the macOS Keychain
  (never in the repo); the public key is in `Info.plist` → `SUPublicEDKey`.
- Release config already has **Hardened Runtime on** (required for notarization).
  There is **no entitlements file**, so the app is non-sandboxed — correct for
  this path.

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
  AX work). On each new `presentPopup()` call, `scrapeTask` is cancelled (so stale
  results never reach the UI); `detachedScrapeTask` is *awaited* inside the new
  `scrapeTask` to drain before a new traversal starts — ensuring at most one AX
  traversal runs at any time despite the synchronous C IPC being uninterruptible.
  On first launch, `setupHotkey()` seeds ⌥⌘K as the factory default hotkey (guarded by
  `didSetDefaultHotkey` so the seed runs only once and never overwrites a deliberate
  "no hotkey" choice). The right-click context menu shows a disabled info row with the
  current hotkey (or "(unset)") so users can discover their trigger without opening
  Settings; it also has Settings…, About KeyMinder, and Quit. `onPermissionGranted`
  calls `setupDoubleTap()` then `presentPopup()` so the double-tap trigger is armed
  the moment Accessibility is granted without requiring a relaunch.
  `setupSleepWakeObserver()` re-arms the trigger on `NSWorkspace.didWakeNotification`
  (sleep/wake can invalidate event monitors). `showWelcomeIfNeeded()` shows the welcome
  wizard 500 ms after the very first launch, guarded by `didShowOnboardingWizard` (a
  distinct flag from the legacy `didShowWelcome`, so all existing users see the wizard
  once on upgrade). On completion the wizard sets `didShowOnboardingWizard = true`,
  clears `onboardingResumeStep`, calls `showMenuBarHint()`, and opens the popup on the
  frontmost app. Closing or quitting the wizard without completing it quits KeyMinder
  and saves the current step to `onboardingResumeStep` so the next launch resumes from
  the same point. `onOpenSettings` (set on `PopupController`) hides the popup then calls
  `SettingsWindowController.show()`. `showMenuBarHint()` displays a 5-second popover on
  the menu-bar icon after wizard completion hinting how to trigger the popup; dismissed
  immediately when the popup opens or the context menu is shown.
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
- `Scraping/SystemShortcutsProvider.swift` — provides macOS system-wide shortcuts
  (Spotlight, Screenshots, Mission Control, etc.) as a `MenuSection`. Two data sources
  are tried in order and merged: (1) `loadViaCGS()` queries the Window Server live using
  three private CoreGraphics symbols (`CGSMainConnectionID`, `CGSGetSymbolicHotKeyValue`,
  `CGSIsSymbolicHotKeyEnabled`) resolved at runtime via `dlopen`/`dlsym`; this gives
  live enabled/disabled state. (2) `loadViaPlist()` parses
  `~/Library/Preferences/com.apple.symbolichotkeys.plist` and `.GlobalPreferences.plist`
  (`NSUserKeyEquivalents`) as a fallback when the private API is unavailable.
  `loadViaCGS()` returns `nil` on macOS versions above 15 (guarded by
  `operatingSystemVersion.majorVersion > 15`) as a safety cap for untested future OS
  releases. Each shortcut carries `isDisabled: Bool`; disabled shortcuts are shown
  greyed-out in the popup when the "Show deactivated system shortcuts" setting is on.
  The `showSystemShortcuts` and `showDeactivatedSystemShortcuts` `UserDefaults` keys
  control visibility (both declared as extensions on `UserDefaults` in `MenuScraper.swift`).

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
  hotkey via Carbon `RegisterEventHotKey`. `register(_:)` is `@discardableResult`
  and returns `Bool` (`true` on `noErr`). The C event-handler callback dispatches
  to the main actor via `DispatchQueue.main.async`.
- `Settings/ThemeSettings.swift` (`@Observable @MainActor`) — singleton managing
  the key-badge accent colour. Stores a `customColor: NSColor?` in `UserDefaults`
  (keyed archive); `nil` means follow `NSColor.controlAccentColor` (system accent).
  `keyAccent: Color` is the computed property read by all popup and onboarding views.
  `setCustomColor(_:)`, `enableCustom()`, and `resetToSystem()` are the mutation
  points.
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
- `Settings/FavouritesStore.swift` (`@Observable @MainActor`) — singleton; persists
  pinned shortcuts in `UserDefaults` keyed by app bundle ID + shortcut title + key
  string. `toggle(_:appBundleID:)` pins or unpins; `isFavourite(_:appBundleID:)` queries.
  Keys are stable across re-scrapes so pins survive popup closes and relaunches.
- `Settings/IgnoreListStore.swift` (`@Observable @MainActor`) — singleton; stores the
  ignored-commands list (`globalTitles`, `perApp`, `appDisplayNames`) and the ignored-apps
  list (`ignoredApps: [bundleID → displayName]`) in `UserDefaults` as a single `IgnoreData`
  JSON blob. `isEnabled` / `showWhenFiltering` are separate bool keys. Pre-seeds four
  global window-management titles on first launch (`didSeedIgnoreList` flag).
  `ignoredTitles(for:)` merges global + per-app sets for the scraper. `isAppIgnored(_:)`
  is called by `AppDelegate.presentPopup()` to silently skip ignored apps.

### UI — Popup

- `UI/Popup/PopupController.swift` (`@MainActor`) — NSPanel lifecycle: `show()` /
  `hide()` with fade-in (0.12 s) and scale (0.98→1.0) / fade-out (0.10 s) animations;
  dismissal monitors (click-outside, Esc, app-switch). `activeVisibleFrame` selects the
  screen containing the mouse cursor (primary), then `NSScreen.main`, then the first
  screen — nil-safe to survive display-reconfiguration races. The panel is always
  centered on that screen. Esc clears a non-empty text filter, then the toggled modifier
  filter, then the favourites filter, then dismisses — each press peels back one layer.
  A local key monitor handles Tab (advance row selection) / Shift-Tab (reverse) / Return
  or numpad Enter (activate selected shortcut) / chord invocation (⌘ or ⌃ held + key:
  if exactly one visible shortcut matches via `matchShortcutEvent(_:)`, it is activated
  directly without dismissing the popup). Permission-poll timer fires
  `onPermissionGranted` the moment `AXIsProcessTrusted()` becomes true.
  Panel is released (`self.panel = nil`) on hide to free the SwiftUI tree while idle.
  Two `flagsChanged` event monitors (global for when another app is frontmost, local for
  when the popup panel is key) call `handleFlagsChanged(_:)` which writes the currently
  held modifier glyphs to `filterModel.heldModifiers` via `extractModifiers(from:)`.
  On popup open, `NSEvent.modifierFlags` seeds `heldModifiers` so the filter is
  immediately correct if modifier keys are already held — as a result, triggering the
  popup via a modifier-key double-tap opens it with that modifier filter active for as
  long as the key is held. `measuredContent` computes
  `fitsWithoutScrolling = naturalHeight ≤ maxPanelHeight` and passes it to the model.
  `savedQuery` and `lastAppBundleID` persist the search query across popup toggles for
  the same app (closing and reopening restores the typed text); the query resets when
  the frontmost app changes. `onOpenSettings` closure is set by `AppDelegate` to hide
  the popup then open Settings. `onGrant` (the onboarding "Grant Access…" button) hides
  the popup before invoking `AccessibilityPermission.requestAccess()` so the system TCC
  dialog is not obscured by the popup panel.
- `UI/Popup/PopupPanel.swift` — non-activating `NSPanel` subclass.
- `UI/Popup/PopupRootView.swift` — contains all popup SwiftUI types:
  - `PopupFilterModel` (`@Observable @MainActor`) — owned by `PopupController`;
    holds the live `query`, fixed `columns` layout, `selectedIndex` for Tab navigation,
    cached `visibleShortcuts` (recomputed on each query/modifier/favourites change),
    `displayableCount`, `matchCount`, and `showsAllItems` (true when all-entries mode is
    on and query ≥ 2 chars). `showOnlyFavourites: Bool` filters the view to pinned rows
    only; toggled by the ★ header button and cleared by Esc (after text/modifier filters).
    `selectNext()` / `selectPrevious()` wrap around. Modifier filtering uses two backing
    stores: `toggledModifiers` (persistent, driven by UI button clicks via
    `toggleModifier(_:)` / `clearToggledModifiers()`) and `heldModifiers` (ephemeral,
    driven by physical key state set by `PopupController`). The computed `modifierFilter`
    is their union and is used for all filtering. `hasToggledModifiers` lets the Esc
    handler clear only persistent state (held keys self-clear on release).
    `fitsWithoutScrolling` (set once at init by the controller) switches `MenuSectionView`
    into dim mode when true. `tipIndex: Int` (backed by `UserDefaults.popupTipIndex`)
    tracks which onboarding tip has been shown; `currentTip: PopupTip?` returns the next
    unshown tip; `advanceTip()` increments the index and persists it.
  - `PopupTip` — enum with three cases (`modifierFilter`, `search`, `favourites`); each
    carries a `text: LocalizedStringKey` shown in the banner.
  - `PopupRootView` — dispatches to `FilterableShortcutsView`, `PopupOnboardingView`,
    or `PopupMessageView`; applies `.regularMaterial` background + border overlay.
  - `FilterableShortcutsView` — header (gear button, app icon, name, count, ★ favourites
    toggle, modifier toggle buttons, auto-focused search field) + optional `TipBannerView`
    (shown when `model.currentTip` is non-nil; dismissing calls `model.advanceTip()`) +
    scrollable shortcut grid; auto-focuses the filter field on appear; scroll-follows the
    selected row. The gear button (`settingsButton`) calls `onOpenSettings`. The ★ button
    appears only when the current app has at least one pinned shortcut and toggles
    `showOnlyFavourites`. Modifier buttons (⌃ ⌥ ⇧ ⌘) are rendered by `ModifierToggle` —
    filled with `ThemeSettings.shared.keyAccent` when active, outlined when not.
  - `TipBannerView` — dismissible tip strip (lightbulb icon + text + ✕ button) rendered
    between header and shortcut grid; accented border, accent background tint, fade-out
    transition on dismiss.
  - `MenuSectionView` — one section card: section header (`.isHeader` VoiceOver trait)
    + optional `SubGroupHeader` labels for named submenu groups + shortcut rows. In normal
    mode the card is absent when no rows pass the filter. In dim mode (`dimMode: true`)
    every keyed row is always rendered; non-matching rows are passed `dimmed: true` and
    only empty sections (no keyed shortcuts at all) are hidden. Section and sub-group
    headers always stay at full opacity in dim mode.
  - `SubGroupHeader` — compact label above a submenu's items inside a section card.
  - `ShortcutRow` — right-aligned key glyphs + command title; hover highlight and
    tap-to-activate when the row has an `axElement`; VoiceOver label via `spokenKeys(_:)`
    (e.g. "⇧⌘N" → "Shift Command N"); Tab-selection highlight. A star button (☆/★) is
    revealed on hover and calls `FavouritesStore.shared.toggle(_:appBundleID:)`. When
    `dimmed: true` both text elements use `Theme.fadedText`, `clickable` is false (no
    tap, no hover, no `.isButton` trait), and the row is invisible to Tab navigation (it
    is absent from `visibleShortcuts`).
  - `PopupMessageView` — centered icon-over-text placeholder for empty / no-app states. `text` is `LocalizedStringKey` (not `String`) so string-literal call sites are localized automatically.
- `UI/Popup/MenuLayout.swift` — layout constants (`columnWidth`, `columnSpacing`,
  `sectionSpacing`, `rowHeight`, `rowSpacing`, `headerHeight`, `subGroupHeaderHeight`)
  and two algorithms: `height(of:)` estimates a section card's rendered height
  (accounting for sub-group headers); `distribute(_:columns:)` partitions sections
  into at most `columns` contiguous slices using binary search on per-column capacity
  to minimise the tallest column.
- `UI/Popup/Theme.swift` — spacing constants and two semantic colours: `fadedText`
  (low-contrast, used for dimmed rows; light grey / dark grey adaptive) and
  `sectionHeaderFill`. The key-badge accent colour has moved to `ThemeSettings`.
- `UI/Popup/PopupOnboardingView.swift` — fallback onboarding screen shown inside the
  popup when Accessibility was not yet granted during the welcome wizard (or if the
  wizard was skipped).

### UI — Onboarding

- `UI/Onboarding/WelcomeWindowController.swift` — singleton `NSWindowController`
  (420 × 460 pt, `.titled | .closable`). `show()` installs `WelcomeView` as an
  `NSHostingView`, centres the window, and resets `wizardCompleted` / `isTerminating`
  flags. `var onComplete: (() -> Void)?` fires via `windowWillClose` when the user
  clicks Done on the last step — wired by `AppDelegate` to persist completion flags
  and open the popup. `var onTryItNow: (() -> Void)?` is wired to
  `AppDelegate.presentPopup()`. Closing the window at any step (title-bar ✕ or the
  "Quit KeyMinder" button on step A) calls `NSApp.terminate(nil)`; the `isTerminating`
  guard prevents a double-terminate if `windowWillClose` fires during the quit sequence.
- `UI/Onboarding/WelcomeView.swift` — 4-step wizard root view (`WelcomeStep` enum:
  `intro`, `permission`, `trigger`, `loginItem`). The custom `init` restores the saved
  step from `UserDefaults.onboardingResumeStep`; if the saved step was `.permission`
  but Accessibility is now trusted, it advances directly to `.trigger`. The `steps`
  computed property filters `.permission` out when `permissionGranted` is true so dot
  indicators and navigation reflect the real step count (3 or 4). `.onChange(of: step)`
  writes the current raw value to `onboardingResumeStep`; `.onChange(of: permissionGranted)`
  auto-advances 800 ms after the grant. Slide transitions use a `goingForward: Bool`
  flag to choose trailing/leading insertion edges. Subviews: `WelcomeIntroStep` (icon
  + feature bullets; "Quit KeyMinder" button calls `onQuit`), `WelcomePermissionStep`
  (lock icon animates open on grant; polls `AXIsProcessTrusted()` every 500 ms via
  `.task`), `WelcomeTriggerStep` (`@Bindable SettingsModel`; `HotkeyBadge` + recording
  buttons; double-tap enable toggle + modifier picker; "Try it now" box calls
  `onTryItNow` and shows a 3-second confirmation), `WelcomeLoginStep` (`@Bindable
  SettingsModel`; Launch at Login toggle + Check for Updates Automatically toggle in
  preference cards; Done calls `onComplete`).

### UI — Settings

- `UI/Settings/SettingsView.swift` — contains three types:
  - `SettingsWindowController` (`@MainActor NSWindowController`) — singleton that
    measures the natural content height via `NSHostingView.fittingSize` at width 420
    before creating the `NSWindow`, so the window always fits its content (including
    at larger accessibility text sizes).
  - `SettingsModel` (`@MainActor @Observable`) — hotkey recording state, UserDefaults
    persistence, `HotkeyManager` registration, login-item toggle, double-tap config
    (`doubleTapEnabled` + `doubleTapModifier`), `showAllMenuItems` (popup content mode),
    `showSystemShortcuts` / `showDeactivatedSystemShortcuts` (system-shortcuts visibility),
    `automaticUpdatesEnabled` (Sparkle `SUEnableAutomaticChecks` key), `debugLoggingEnabled`
    toggle, and `registrationFailed: Bool` (set when Carbon rejects a hotkey; cleared on
    each new recording attempt and on clear). `SettingsModel` is reused inside
    `WelcomeView` for the trigger and login-item steps so settings edited in the wizard
    are immediately persisted via the same `didSet` observers.
  - `SettingsView` — two tabs: **General** (Global Shortcut with hotkey badge +
    record/change/clear and "Shortcut already in use" error; Launch at Login toggle;
    Double-tap Trigger with enable toggle + modifier picker; Popup Content "Show all menu
    entries" toggle + "Show system shortcuts" toggle + "Show deactivated system shortcuts"
    sub-toggle; Appearance colour picker + "Follow system accent colour" toggle
    writing to `ThemeSettings`) and **Advanced** (Ignored Commands with master enable
    toggle, "Show when filtering" sub-toggle, global list, per-app list; Ignored Apps
    list; Developer debug logging toggle).
  - `HotkeyBadge` — pill badge showing current hotkey or recording prompt; `@State`
    owns `SettingsModel`. Uses a `@ViewBuilder` `labelText` property with explicit
    `Text("Type your shortcut…")` / `Text(verbatim: hk.displayString)` / `Text("Not set")`
    branches so the keyboard shortcut display string bypasses localization lookup.

### Assets & support

- `Assets.xcassets/` — `AppIcon.appiconset` (10 PNG slots, 16 pt → 512 pt @1×/@2×)
  and `AccentColor.colorset` (system accent colour).
- `Localizable.xcstrings` — String Catalog; source language `en`; 50 keys translated
  into ar, da, de, es, fi, fr, he, hi, it, ja, nb, nl, pt, sv, zh-Hans, zh-Hant.
  `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` and
  `SWIFT_EMIT_LOC_STRINGS = YES` are set, so building in Xcode automatically extracts
  new `Text("…")` literals into the catalog. AppKit strings (NSMenuItem titles,
  `NSWindow.title`) use `String(localized:)` explicitly.
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
- `KeyMinderTests/SpokenKeysTests.swift` — 26 cases for `spokenKeys(_:)`: modifier
  glyphs, special keys, Space word-token, Fn keys, regular letters and digits.

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
- **Localization**: SwiftUI `Text("…")`, `Button("…")`, `Toggle("…")`, etc. accept
  `LocalizedStringKey` implicitly — no wrapping needed for new UI strings. AppKit
  strings (NSMenuItem, NSWindow.title) need explicit `String(localized:)`. The build
  auto-populates `Localizable.xcstrings`; add translations there for each new key.
  Test a language with scheme → Options → App Language.
- **Versioning: every commit bumps the patch (last) number** of
  `MARKETING_VERSION` and is tagged `vX.Y.Z`. Canonical sources of truth:
  `MARKETING_VERSION` in `KeyMinder.xcodeproj/project.pbxproj`, or
  `git tag --sort=-v:refname | head -1`.

## Known limitations / next up

- AX scraping runs on a background `Task.detached`; the main thread is unblocked, but
  the AX IPC itself is synchronous C code with no Swift cancellation checkpoints — a
  busy target app can still delay the popup until the 1 s AX timeout fires.
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
