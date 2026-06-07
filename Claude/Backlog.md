# KeyMinder Backlog

Items are rough ideas, not commitments. No priority order.

---

## Known Issues

### Ignored Commands — "Show when filtering" unreliable (v0.1.71)

Ignored rows are supposed to appear dimmed when the user types a query that matches them, but the behaviour is inconsistent. Needs investigation into how `showWhenFiltering` interacts with `MenuSectionView`'s dim-mode logic and the `visibleShortcuts` cache in `PopupFilterModel`.

---

## Auto-updater

Integrate **Sparkle** so users receive update notifications and can install new
versions without manually downloading a DMG. Sparkle is the de-facto standard
for Developer ID-distributed macOS apps and supports delta updates,
release notes in the update sheet, and silent background checks.

**Notes:** requires hosting an `appcast.xml` alongside the DMG; the release
script would need to generate and sign the appcast entry. Sparkle's XPC
service model is compatible with Hardened Runtime.

---

## Tip jar / support link

Add a **"Support KeyMinder"** item to the right-click context menu (and/or
the About panel) that opens a Ko-fi, GitHub Sponsors, or similar page.

**Notes:** no in-app payment processing needed — just a URL open.

---

## Right-click to assign a shortcut

Right-clicking a command row could open **System Settings → Keyboard →
Keyboard Shortcuts → App Shortcuts** with the app pre-filled, so the user
can assign or change the shortcut without navigating there manually.

**Notes:** the deep-link URL scheme for System Settings panels is
`x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts`; the
app name field would need to be pre-filled via AppleScript or by writing a
temporary `com.apple.symbolichotkeys` plist entry. Needs investigation —
macOS does not expose a direct API to pre-populate the Add Shortcut sheet.

---

## Invoke command by pressing its shortcut keys in the popup

While the popup is open, pressing the exact shortcut for a visible command
(e.g. ⌘S) could fire the command in the target app rather than modifying the
search field.

**Notes:** the modifier-filter and search field already intercept key events,
so the implementation needs to distinguish "shortcut chord" from "search
input". Proposal: if the key event matches exactly one visible shortcut
*and* the search field is empty, treat it as an invocation; otherwise let it
fall through to the field. The existing `AXUIElementPerformAction` path in
`ShortcutActivator` would handle the actual dispatch.

---

## Emoji search

A dedicated search mode (or a separate popup trigger) that lets the user
search macOS emoji by name and copy or insert the result — similar to the
system emoji picker but keyboard-driven and accessible from the same trigger
as the shortcut popup.

**Notes:** emoji metadata (names, keywords) ships with macOS in
`/System/Library/Input Methods/EmojisInputMethod.app`; alternatively use a
bundled JSON list. Insertion could use `CGEventCreateKeyboardEvent` to paste.

---

## Special character search

Search Unicode characters (arrows, math symbols, diacritics, currency, etc.)
by name or category, then copy to clipboard or insert at the cursor.

**Notes:** could share UI infrastructure with the emoji search above. The
Unicode character database can be bundled as a compact lookup table (~2 MB
for names + codepoints).

---

## Favorites / pinned shortcuts

Let users pin shortcuts — either globally (always shown at the top regardless
of frontmost app) or per-app — so frequently used commands are one glance away
without searching.

**Notes:** storage in `UserDefaults` keyed by app bundle ID + menu item title.
Pinned rows would appear in a "Favorites" section above the regular sections.

---

## Export cheat sheet

A button or right-click option to copy the currently visible shortcuts as
**Markdown** or plain text — useful for documentation, onboarding teammates,
or printing a reference card.

**Notes:** straightforward serialization of `AppShortcuts`; could also
support PDF via `WKWebView` print-to-PDF.

---

## Shortcut conflict detector

Highlight (with a warning icon or color) any shortcut that appears more than
once in the frontmost app's menu — a common source of confusion when
third-party plugins or app updates silently duplicate a binding.

**Notes:** conflicts are detectable purely from the already-scraped
`AppShortcuts` data; no additional AX calls needed.

---

## Global shortcuts from all running apps

Show hotkeys registered by every running app (Raycast, Alfred, etc.) alongside the frontmost app's menu shortcuts — a "what global shortcuts are active right now" view.

**Background:** `GetEventHotKeyList` does not exist in HIToolbox. The CGS non-symbolic hotkey APIs (`CGSGetHotKey`, `CGSGetHotKeyRepresentation`) were probed empirically (see `internal/Experimental_Global_Hotkeys_2026-06-07_v2.md`): the Window Server returns `kCGErrorInvalidConnection` (1002) for any attempt to read another process's registered hotkeys — cross-process enumeration is definitively blocked.

**Two viable approaches (not mutually exclusive):**

1. **Per-app plist reading** — read the hotkey preference key from each popular app's `~/Library/Preferences/` plist. Accurate, zero latency, works for sandboxed apps. Requires per-app maintenance (schema changes break it silently). Practical scope: top ~10 apps users commonly run alongside KeyMinder (Raycast, Alfred, Bartender, etc.).

2. **Passive `CGEventTap` observation** — register a listen-only tap on `kCGKeyDownMask`. Combos consumed before the tap sees them can be inferred as taken. Generalises without per-app knowledge; requires Accessibility (already granted). Limitation: only surfaces shortcuts that are actually pressed during a session — incomplete at first launch.

**Hard limitation either way:** Carbon stores only keyCode + modifiers in the Window Server, not the action label. We can show "⌥Space" but not "Show Raycast". App name as group title is the best we can do unless a lookup table is maintained for known apps.

---

## System-wide shortcuts

Show macOS system shortcuts (Spotlight, Screenshots, Mission Control, etc.)
in a dedicated section, sourced from
`com.apple.symbolichotkeys` in `~/Library/Preferences/.GlobalPreferences.plist`.

**Notes:** already listed as a planned phase in CLAUDE.md.

---

## Compact / keys-only mode

A display option that shows only the key badge column (no command title) for
users who already know what the shortcuts do and want maximum density.

---

## Localisation

Translate the app UI to common languages. Menu item titles scraped via AX are
already in the system locale of the target app, so they require no extra work.
Only the KeyMinder-owned strings (settings labels, onboarding text, context menu
items, error messages) need translation.

**Notes:** straightforward `Localizable.strings` / `String(localized:)` work.
Priority locales: French, German, Spanish, Japanese, Simplified Chinese.

---

## User-selectable key-highlight colour

The key-badge accent colour is currently hardcoded to green. Allow the user to
choose a colour in Settings, defaulting to the system accent colour from System
Settings → Appearance.

**Notes:** system accent colour is readable at runtime via
`NSColor.controlAccentColor`. The setting would be stored in `UserDefaults` as a
raw colour (or a sentinel value meaning "follow system"). `Theme.keyAccent` in
`UI/Popup/Theme.swift` is the single point of change — it already drives all key
badge fills.
