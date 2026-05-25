# KeyMinder

A macOS menu bar app that instantly shows the keyboard shortcuts of whichever app you're currently using, grouped by menu.

## Why KeyMinder?

Instead of hunting through menus to find shortcuts, KeyMinder pops up a clean overview of every keyboard shortcut in the frontmost app — triggered by a hotkey or double-tap, dismissed the same way.

## Requirements

- macOS 26 or later
- Accessibility permission (required to read other apps' menus)

## Why not on the App Store?

KeyMinder reads other apps' menus via the macOS Accessibility API. This is fundamentally incompatible with the App Store's mandatory App Sandbox — no entitlement exists to re-open this capability inside the sandbox. The same constraint applies to similar tools like KeyCue and Shortcat.

KeyMinder is distributed as a notarized Developer ID build.

## Building from source

Open `KeyMinder.xcodeproj` in Xcode and press ⌘R. Xcode 26 required.

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
