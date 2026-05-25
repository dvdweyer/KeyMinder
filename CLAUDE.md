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

- `KeyMinderApp.swift` — `@main`; empty `Settings` scene. All UI is driven by `AppDelegate`.
- `AppDelegate.swift` (`@MainActor`) — owns the `NSStatusItem` (left-click toggles
  the popup, right-click shows Grant/Quit menu), `FrontmostAppMonitor`, and `PopupController`.
- `Monitoring/FrontmostAppMonitor.swift` — tracks the frontmost app via
  `NSWorkspace` notifications, ignoring KeyMinder itself.
- `Accessibility/AccessibilityPermission.swift` — trust check / prompt / open Settings.
- `Scraping/MenuScraper.swift` — AX traversal of the menu bar → `[MenuSection]`.
  **Submenus are currently flattened** into the parent menu.
- `Scraping/ShortcutFormatter.swift` — decodes the AX modifier mask
  (shift=1, option=2, control=4, no-command=8) plus char/glyph/virtual-key into
  display symbols (⌃⌥⇧⌘ + key).
- `Model/ShortcutModel.swift` — `Shortcut`, `MenuSection`, `AppShortcuts`, `PopupContent`.
- `UI/Popup/` — `PopupController` (NSPanel lifecycle, sizing, dismissal),
  `PopupPanel` (non-activating floating panel), `PopupRootView` (the grid),
  `MenuLayout` (greedy column balancing), `Theme` (colors/metrics),
  `PopupOnboardingView`.

The Xcode project uses a **file-system-synchronized group** (objectVersion 70):
new `.swift` files under `KeyMinder/` are picked up automatically — no need to
edit `project.pbxproj`.

## Conventions

- macOS 14+ (deployment target 14.0); Swift 5 language mode (`SWIFT_VERSION = 5.0`).
  Newest APIs in use all land at 14.0: `@Observable`, `.scrollBounceBehavior`,
  `MainActor.assumeIsolated` — so no `if #available` branching is needed.
- Light/dark handled automatically via `.regularMaterial` + semantic colors.
- **Versioning: every commit bumps the patch (last) number** of
  `MARKETING_VERSION` and is tagged `vX.Y.Z`. Canonical sources of truth:
  `MARKETING_VERSION` in `KeyMinder.xcodeproj/project.pbxproj`, or
  `git tag --sort=-v:refname | head -1`.

## Known limitations / next up

- **No app icon yet:** there is no `Assets.xcassets` in the project, though
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` is set. A full icon set
  (incl. 1024×1024) is needed before any release/distribution build.
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
