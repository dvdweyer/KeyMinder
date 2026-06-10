# KeyMinder Backlog

Items are rough ideas, not commitments. No priority order.

---

## Known Issues

~~### Ignored Commands — "Show when filtering" unreliable (v0.1.71)~~ **Fixed in v0.1.86.**

### DMG download saves as .man in Safari

Safari maps the server's `Content-Type: application/x-troff-man` response to
a `.man` file extension via macOS UTI. Root cause: Cloudflare cached the wrong
MIME type before the `.htaccess` fix (`AddType`/`ForceType application/octet-stream`)
was deployed. Chrome and Firefox ignore the Content-Type for downloads and use
the URL filename, so they are unaffected.

A `.htaccess` fix and a Cloudflare Cache Rule (bypass cache for `*.dmg`) are
already in place. Purging the Cloudflare cache for the specific URL did not
resolve it for Safari. The website download link has been reverted to ZIP in
the meantime. Needs further investigation — possibly a Cloudflare Transform
Rule to override the response Content-Type header at the edge.

---

~~## Auto-updater~~ **Shipped in v0.1.84 (Sparkle).**

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

## Growth / community nudges

A small set of in-app prompts that appear after the user has had a chance to
form a habit with KeyMinder. Goal: surface discovery actions to engaged users
without being annoying.

**Trigger logic (shared):** show after N popup opens (e.g. 20) and only once
per action, guarded by a `UserDefaults` bool (`didPromptGitHubStar`,
`didPromptAlternativeTo`, etc.). A single dismissal marks it done permanently —
no repeat asks.

**Surface:** a dismissible banner inside the popup (reuse `TipBannerView`) or
a one-off item in the right-click context menu that removes itself after being
clicked.

### Star on GitHub

Banner or context-menu item: "Enjoying KeyMinder? Star it on GitHub ↗" →
opens `https://github.com/dvdweyer/KeyMinder`. Star count is public social
proof and helps discoverability on GitHub Trending.

### Heart on AlternativeTo

"List us on AlternativeTo ↗" → opens the KeyMinder listing page. A heart
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
   `hello@keyminder.app` (or similar) with a subject line like "KeyMinder
   Feedback". Zero infrastructure; replies land in your inbox. Simplest to
   ship.
2. **Pre-filled GitHub Issue URL** — opens a browser to a new issue form with
   a bug-report or feature-request template pre-selected. Requires users to
   have a GitHub account; self-selects for technical users.
3. **Short web form** — a Tally / Typeform / Google Form URL. No account
   required for the user; responses aggregate in a spreadsheet. Slight friction
   of opening a browser tab.

**Suggested surface:** a "Send Feedback…" item in the right-click context menu
(below "Settings…", above "About"). One `NSOpenPanel`-free `NSWorkspace
.open(url)` call.

**Notes:** whichever option is chosen, the app version (`Bundle.main
.infoDictionary["CFBundleShortVersionString"]`) and macOS version
(`ProcessInfo.processInfo.operatingSystemVersionString`) should be appended to
the mailto body / URL query string automatically so bug reports arrive with
context.

---

### Submit to Mac app directories

Manual/one-off tasks (not in-app), but worth tracking here so they don't fall
through the cracks:

- [MacMenuBar.com](https://macmenubar.com) — submit form for menu-bar apps.
- [OpenAlternative.to](https://openalternative.to) — open-source alternatives
  directory; submit via their GitHub repo.
- [Awesome macOS](https://github.com/iCHAIT/awesome-macOS) — PR to add
  KeyMinder under "Productivity".
- [Setapp blog / newsletter](https://setapp.com) — not a distribution channel,
  but a potential editorial mention.

---

~~## Homebrew Cask distribution~~ **Shipped — `brew install --cask dvdweyer/keyminder/keyminder`.**

~~Distribute KeyMinder via a [Homebrew Cask](https://github.com/Homebrew/homebrew-cask) so users can install and update with `brew install --cask keyminder`.~~

~~**Notes:** requires a notarized `.dmg` or `.zip` artifact at a stable URL (the Sparkle release zip already qualifies). Submit a PR to `homebrew/homebrew-cask` with a `keyminder.rb` cask definition pointing at the GitHub release asset. Version bumps can be automated via a GitHub Action that updates the cask SHA256 and URL on each release. Alternatively, host a tap (`dvdweyer/homebrew-keyminder`) for faster iteration before upstreaming to the main cask repo.~~

---

## Tip jar / support link

Add a **"Support KeyMinder"** item to the right-click context menu (and/or
the About panel) that opens a Ko-fi, GitHub Sponsors, or similar page.

**Notes:** no in-app payment processing needed — just a URL open.

---

