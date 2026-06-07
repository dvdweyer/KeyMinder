# KeyMinder Backlog

Items are rough ideas, not commitments. No priority order.

---

## Known Issues

### Ignored Commands — "Show when filtering" unreliable (v0.1.71)

Ignored rows are supposed to appear dimmed when the user types a query that matches them, but the behaviour is inconsistent. Needs investigation into how `showWhenFiltering` interacts with `MenuSectionView`'s dim-mode logic and the `visibleShortcuts` cache in `PopupFilterModel`.

---

## Interactive onboarding tour

A guided walkthrough that introduces new users to KeyMinder's key features and
settings — triggered automatically on first launch (after the Accessibility grant)
or manually via a "Take the tour…" item in the right-click context menu.

Each step would highlight one concept with a brief explanation and, where possible,
a live demonstration:

1. **Trigger** — show the global hotkey and double-tap option; invite the user to
   try opening the popup.
2. **Search** — type-to-filter; modifier key buttons (⌃ ⌥ ⇧ ⌘); dim mode when
   all shortcuts fit on screen.
3. **Favourites** — hover a row to reveal the star; ★ header button; Esc to clear.
4. **Run a command** — click or Tab + Return to activate a shortcut directly.
5. **System shortcuts** — the dedicated section for Spotlight, Screenshots, etc.
6. **Settings highlights** — all-entries mode, Ignored Commands, custom accent colour.

**Implementation notes:** a `TourController` owned by `AppDelegate` could drive a
sequence of lightweight popovers anchored to the menu-bar icon or the popup panel
itself, advancing on user action or a timeout. The existing `showHintPopover()`
infrastructure in `AppDelegate` (used after first-launch Settings close) is a
natural starting point. State tracked in `UserDefaults` (`didCompleteTour: Bool`)
so it runs once automatically and can be re-triggered on demand.

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

## Compact / keys-only mode

A display option that shows only the key badge column (no command title) for
users who already know what the shortcuts do and want maximum density.

---

