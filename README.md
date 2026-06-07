# KeyMinder

A macOS menu bar app that instantly shows the keyboard shortcuts of whichever app you're currently using, grouped by menu.

## Why KeyMinder?

Instead of hunting through menus to find shortcuts, KeyMinder pops up a clean overview of every keyboard shortcut in the frontmost app — triggered by a global hotkey (default ⌥⌘K) or a double-tap of a modifier key, dismissed the same way. Type to filter the list instantly, or hold/toggle modifier keys (⌃ ⌥ ⇧ ⌘) to filter by exact modifier combination. When all shortcuts fit on screen without scrolling, non-matching rows dim in place instead of collapsing, keeping the layout stable.

Pin frequently used shortcuts as favourites (hover a row for the star button) and filter to them instantly with the ★ header button. Suppress noisy commands globally or per-app with Ignored Commands in Settings → Advanced. Use the gear button in the popup header to jump straight to Settings.

KeyMinder checks for updates automatically and notifies you when a new version is available. Use "Check for Updates…" in the right-click context menu to check manually.

## Requirements

- macOS 14 (Sonoma) or later
- Accessibility permission (required to read other apps' menus)

## Languages

KeyMinder is fully localized. The interface adapts automatically to your Mac's system language:

Arabic, Danish, Dutch, Finnish, French, German, Hebrew, Hindi, Italian, Japanese, Norwegian, Portuguese, Simplified Chinese, Spanish, Swedish, Traditional Chinese, and English.

## Why not on the App Store?

KeyMinder reads other apps' menus via the macOS Accessibility API. This is fundamentally incompatible with the App Store's mandatory App Sandbox — no entitlement exists to re-open this capability inside the sandbox. The same constraint applies to similar tools like KeyCue and Shortcat.

KeyMinder is distributed as a notarized Developer ID build.

## Building from source

Open `KeyMinder.xcodeproj` in Xcode and press ⌘R. Xcode 15 or later required.

**Important:** do not build into the project folder if it lives in iCloud Drive — build products acquire iCloud extended attributes that cause codesign to fail. Build to the default DerivedData location or `/tmp`.

## Installing a development build

After building, copy to `/Applications` before granting Accessibility permission — macOS TCC does not register apps run from DerivedData or `/tmp`:

```bash
cp -R /tmp/KeyMinder-build/Build/Products/Debug/KeyMinder.app /Applications/
xattr -cr /Applications/KeyMinder.app
open /Applications/KeyMinder.app
```

## License

MIT
