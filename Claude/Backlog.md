# KeyMinder Backlog

Items are rough ideas, not commitments. No priority order.

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

## System-wide shortcuts

Show macOS system shortcuts (Spotlight, Screenshots, Mission Control, etc.)
in a dedicated section, sourced from
`com.apple.symbolichotkeys` in `~/Library/Preferences/.GlobalPreferences.plist`.

**Notes:** already listed as a planned phase in CLAUDE.md.

---

## Compact / keys-only mode

A display option that shows only the key badge column (no command title) for
users who already know what the shortcuts do and want maximum density.
