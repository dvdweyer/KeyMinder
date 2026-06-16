# Changelog

All notable changes to KeyMinder are listed here. Grouped by significant milestone; individual patch releases are tagged `vX.Y.Z` in git.

## v1.0.149–v1.0.153 — Security hardening (2026-06-16)

- Scraped menu-item titles and `NSUserKeyEquivalents` keys sanitised at the AX trust boundary (bidi overrides, C0/C1 controls, strings longer than 256 characters stripped)
- Markdown export escapes special characters; double-backtick fencing for shortcut keys containing a backtick
- Shortcut activation re-reads the live enabled state and title of the target menu item at press time; disabled items are skipped, title mismatches logged
- Sparkle appcast now carries a `minimumAutoupdateVersion` floor, blocking silent rollback to a prior release
- Carbon hotkey handler verifies event signature before acting

## v1.0.120–v1.0.148 — Quiz mode, alternate icons, performance (2026-06-13–15)

- **Quiz mode**: test yourself on keyboard shortcuts for the frontmost app; favourites-only toggle; keyboard-driven with auto-advance
- **Alternate menu bar icons**: choose ⌘, ⌥, or ⌃ icon variants in Settings
- **Disambiguation overlay**: clicking a shortcut on an ignored-menu item shows an overlay explaining why it is suppressed
- Dock icon shown while Settings or About window is open
- Pre-cache: menus are scraped in the background the moment an app becomes frontmost, eliminating popup latency on subsequent trigger
- Filter: dim mode correctly stays off while a query is active (regression fix from v1.0.130)
- Extensive performance pass: reduced allocations in PopupFilterModel, SettingsModel, and the AX traversal path
- Beta release channel: Settings toggle opts into beta builds via Sparkle

## v1.0.104–v1.0.119 — Homebrew, separators, widescreen layout (2026-06-10–11)

- Homebrew tap (`dvdweyer/keyminder`) with copy-button install instructions on website
- Menu separators rendered as horizontal rules in the popup
- Popup widens to maximise columns when screen space allows
- "Show All Menu Entries" setting to list items without shortcuts

## v0.1.84–v0.1.106 — Auto-updater, system shortcuts, ignored lists (2026-06-07–10)

- **Sparkle auto-updater**: background update checks with user notification
- **System shortcuts**: queries Window Server live for enabled/disabled state; toggle to hide deactivated entries
- **Ignored Commands** and **Ignored Apps**: suppress noisy entries globally or per-app
- **Favourites**: pin shortcuts with a star button; ⌘D toggles favourite for the keyboard-selected row; ★ header button filters to pinned items
- **Export cheat sheet**: copy or save shortcuts as Markdown
- Click a shortcut row to invoke it in the target app (`AXPress`)
- Settings tabs; user-selectable key-badge accent colour
- Localisation: 17 languages (Arabic, Danish, Dutch, Finnish, French, German, Hebrew, Hindi, Italian, Japanese, Norwegian, Portuguese, Simplified Chinese, Spanish, Swedish, Traditional Chinese, English)

## v0.1.58–v0.1.83 — Modifier filter, dim mode, VoiceOver (2026-06-02–07)

- **Modifier key filter**: hold or toggle ⌃ ⌥ ⇧ ⌘ in the popup to filter by exact modifier combination
- **Dim mode**: when all shortcuts fit without scrolling, non-matching rows dim in place instead of collapsing — keeps layout stable
- **Double-tap trigger**: double-tap a modifier key to show/hide the popup
- VoiceOver labels and accessibility states on all interactive elements
- Type-to-filter with match highlighting

## v0.1.1–v0.1.57 — Initial release and foundations (2026-05-23–06-02)

- Initial menu-bar app: scrapes the frontmost app's menus via the Accessibility API and shows all keyboard shortcuts grouped by menu
- Global hotkey (⌥⌘K default, user-configurable)
- Multi-column layout sized to content; multi-display centering
- Launch at Login (SMAppService)
- Unit test suite (DoubleTapTrigger state machine, PopupFilterModel, MenuLayout, shortcut formatting)
- Deployment target: macOS 14 (Sonoma)
