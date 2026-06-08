# KeyMinder Backlog

Items are rough ideas, not commitments. No priority order.

---

## Known Issues

~~### Ignored Commands — "Show when filtering" unreliable (v0.1.71)~~ **Fixed in v0.1.86.**

---

~~## Auto-updater~~ **Shipped in v0.1.84 (Sparkle).**

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

