# KeyMinder Backlog

Items are rough ideas, not commitments. No priority order.

---

## Known Issues

~~### Ignored Commands — "Show when filtering" unreliable (v0.1.71)~~ **Fixed in v0.1.86.**

---

~~## Auto-updater~~ **Shipped in v0.1.84 (Sparkle).**

---

~~## Alternative menu-bar icon~~ **Shipped — Settings → General → Double-tap Trigger (auto-syncs to trigger key; manual override via menu-bar icon style).**

---

~~## Show Dock icon when Settings or About window is open~~ **Shipped — `DockIconManager` switches activation policy dynamically (Settings, About, Quiz windows).**

---

~~## Quiz mode~~ **Shipped — right-click context menu "Quiz Mode…".**

---

~~## Show only visible menu items until filtering starts~~ **Shipped — "Only show when searching" sub-toggle under "Show all menu entries" (Settings → Popup).**

---

## User-defined shortcuts

Some apps register global shortcuts outside the standard menu system (e.g. via `CGEventTap`,
Carbon `RegisterEventHotKey`, or custom input handling) and therefore show up with no shortcuts
in the KeyMinder popup. Let users manually add their own shortcut entries for these apps.

**Proposed UX:** an editor (accessible from the popup or Settings) where the user picks a target
app, types a key combination, and gives it a label. User-defined entries are stored in
`UserDefaults` (or a small JSON file) and merged with scraped results at display time, shown
with a visual indicator (e.g. a pencil badge) to distinguish them from AX-sourced shortcuts.

**Notes:**
- Entries should be editable and deletable.
- Executing user-defined shortcuts via `ShortcutActivator` may not be possible without a stored
  `axElement`; execution could fall back to a synthetic `CGEvent` key press.
- Import/export (share a shortcut set with other KeyMinder users) is a natural follow-on.

---

## Single-letter shortcut execution

Single-letter shortcuts (e.g. Reeder's `j`, `k`, `r` — no modifiers) should be directly executable
from the popup, the same way modifier-key shortcuts already work via `ShortcutActivator`.

**Problem:** the popup intercepts unmodified key presses to drive the search filter, so bare-letter
shortcuts can't be dispatched to the target app by typing them.

**Notes:** `ShortcutActivator` already calls `AXUIElementPerformAction(kAXPressAction)` on the stored
`axElement` — the plumbing exists. The challenge is disambiguation: clicking a row (mouse path) should
fire the action; typing a letter should still filter. A row-click-to-execute approach (matching what
modifier shortcuts already do on click) is the likely path of least resistance.

---

## Option-key alternate menu items

In macOS, holding Option swaps certain menu items for alternates (e.g. "Close" → "Close All", "Get Info" → "Show Inspector"). Showing this live behaviour in the KeyMinder popup would be a useful differentiator.

**Investigation result (2026-06-12, v1.0.118):** not buildable via the AX API without unacceptable side effects. `kAXChildrenAttribute` does not include hidden alternate items when menus are closed — confirmed across Safari, Finder, and Xcode with debug logging enabled. The AX bridge only exposes alternates while the menu is open and being tracked by NSMenu's menu manager. The only way to force this is to physically open each menu via `kAXPressAction`, which flashes menus on screen and is intentionally excluded.

**If Apple widens the AX API in a future macOS release** (e.g. a `kAXAlternateMenuItems` attribute or equivalent), revisit. Until then, the feature is blocked at the platform level.

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

A display option that hides the command title and shows only the key badge (e.g. `⇧⌘N`) for each shortcut. Aimed at users who already know what their shortcuts do and just need a quick reminder of the exact key combination — a cheat sheet reduced to pure glyphs.

The narrower rows allow more shortcuts on screen before scrolling, and the reduced popup width takes up less screen real estate. Could also enable more columns in the multi-column layout before the panel reaches the screen edge.

---

## Growth / community nudges

A small set of in-app prompts that appear after the user has had a chance to
form a habit with KeyMinder. Goal: surface discovery actions to engaged users
without being annoying.

**Trigger logic (shared):** show after N popup opens and only once per action,
guarded by a `UserDefaults` bool. A single dismissal marks it done permanently.

**Surface:** a dismissible banner inside the popup (reuse `NudgeBannerView`) or
a one-off item in the right-click context menu that removes itself after being
clicked.

~~### Star on GitHub~~ **Shipped — `NudgeBannerView` with `.githubStar` case; shown after 10 popup opens once all tips are seen.**

### Heart on AlternativeTo

"Like us on AlternativeTo ↗" → opens the KeyMinder listing page. A heart
costs the user one click and lifts the listing in search results for people
looking for KeyCue alternatives.

### Request a review / testimonial

"Leave a review on AlternativeTo ↗" (or a short Typeform / Google Form).
Written reviews carry more weight in search results and give pull-quote
material for the website.

### ProductHunt upvote

If/when a PH launch happens: one-time banner → "We launched on Product Hunt
today — an upvote helps a lot ↗". Time-box to launch day (store launch date in
a remote config or hardcode it).

### Share with a colleague

"Know a Mac power-user who'd love this?" → copies a pre-drafted message to the
clipboard (e.g. "I use KeyMinder to instantly see all keyboard shortcuts for
the app I'm in — it's free: https://keyminder.app"). No URL scheme needed;
`NSPasteboard` write only.

### In-app feedback channel

A low-friction way for users to send feedback directly to the developer —
without leaving the app or navigating to a website.

**Options (pick one):**

1. **mailto: link** — opens the user's default mail client pre-addressed to
   `info@keyminder.app` with a subject line like "KeyMinder Feedback". Zero
   infrastructure; replies land in your inbox. Simplest to ship.
2. **Pre-filled GitHub Issue URL** — opens a browser to a new issue form with
   a bug-report or feature-request template pre-selected. Requires users to
   have a GitHub account; self-selects for technical users.
3. **Short web form** — a Tally / Typeform / Google Form URL. No account
   required for the user; responses aggregate in a spreadsheet. Slight friction
   of opening a browser tab.

**Suggested surface:** a "Send Feedback…" item in the right-click context menu
(below "Settings…", above "About"). One `NSWorkspace.open(url)` call.

**Notes:** whichever option is chosen, the app version and macOS version should
be appended to the mailto body / URL query string automatically so bug reports
arrive with context.

---

## Submit to Mac app directories

- ~~[MacMenuBar.com](https://macmenubar.com/keyminder/)~~ **Live.**
- ~~[AlternativeTo](https://alternativeto.net/software/keyminder/about/)~~ **Live.**
- [OpenAlternative.to](https://openalternative.to) — open-source alternatives directory; submit via their GitHub repo.
- [Awesome macOS](https://github.com/iCHAIT/awesome-macOS) — PR to add KeyMinder under "Productivity".
- [Setapp blog / newsletter](https://setapp.com) — not a distribution channel, but a potential editorial mention.
