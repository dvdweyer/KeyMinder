# Security Fixes — 2026-06-01

Source: `Claude/AUDIT.md`, findings F-01, F-02, F-04, F-05, F-07, F-NEW-1.  
Six changes total. None alters behaviour visible to the user.

---

## Fix 1 — F-01 (Low): Replace force cast with conditional cast in `MenuScraper`

### What
`MenuScraper.element(_:_:)` casts a `CFTypeRef` to `AXUIElement` with `as!` after a
`CFGetTypeID` check. The guard makes the cast safe in normal operation, but if the AX
runtime returns an unexpected type for any reason (corrupt attribute, future API change),
the force cast causes a hard crash rather than a graceful `nil` return. Swapping to `as?`
keeps the return type (`AXUIElement?`) consistent and turns any surprise type mismatch into
a `nil` that the caller already handles.

### Why it is safe
The return type of the method is already `AXUIElement?`. All callers guard on `nil`. The
change is behaviour-equivalent in every case the type ID check passes, and turns an
unrecoverable crash into an ignored `nil` in the one theoretical case it does not.

### File changed

**`KeyMinder/Scraping/MenuScraper.swift` — `element(_:_:)` helper**

```swift
// BEFORE
private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let raw = value(element, attribute),
          CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return (raw as! AXUIElement)
}

// AFTER
private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let raw = value(element, attribute),
          CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return raw as? AXUIElement
}
```

### Prompt

> In `KeyMinder/Scraping/MenuScraper.swift`, find the private static helper `element(_:_:)`.
> It currently ends with `return (raw as! AXUIElement)`. Replace the force cast
> `(raw as! AXUIElement)` with the conditional cast `raw as? AXUIElement`. The surrounding
> guard, return type, and all other code must remain unchanged.

---

## Fix 2 — F-02 (Medium): Downgrade menu title log privacy from `.public` to `.private`

### What
Three log statements emit third-party app content (submenu names and shortcut titles) with
`privacy: .public`, which causes them to appear unredacted in `sysdiagnose` archives,
`log collect` output, and any tool that reads the unified log. Changing the `title`,
`hint`, and `shortcut.title` interpolations to `privacy: .private` redacts them in
collected logs while preserving them in live `log stream` output (where the operator is
already running as the same user and explicitly watching the stream). Integer values
(`itemCount`) are harmless and can stay `.public`.

### Why it is safe
The privacy level is a logging annotation only — it controls how the value is encoded in
the system log database. It has no effect on the variables themselves, the AX scraping
logic, or anything the user sees in the UI. The `log stream` command used in CLAUDE.md
still shows the full string for the developer watching live; it is only static captures
that are redacted.

### Files changed

**`KeyMinder/Scraping/MenuScraper.swift` — first empty-submenu log**

```swift
// BEFORE
Logger.scraper.info("Submenu '\(title, privacy: .public)' yielded 0 items (\(itemCount, privacy: .public) child items\(hint, privacy: .public))")

// AFTER
Logger.scraper.info("Submenu '\(title, privacy: .private)' yielded 0 items (\(itemCount, privacy: .public) child items\(hint, privacy: .private))")
```

**`KeyMinder/Scraping/MenuScraper.swift` — second empty-submenu log**

```swift
// BEFORE
Logger.scraper.info("Nested submenu '\(title, privacy: .public)' yielded 0 items (\(itemCount, privacy: .public) child items\(hint, privacy: .public))")

// AFTER
Logger.scraper.info("Nested submenu '\(title, privacy: .private)' yielded 0 items (\(itemCount, privacy: .public) child items\(hint, privacy: .private))")
```

**`KeyMinder/Accessibility/ShortcutActivator.swift` — AX press failure log**

```swift
// BEFORE
Logger.accessibility.error("AX press failed for '\(shortcut.title, privacy: .public)'")

// AFTER
Logger.accessibility.error("AX press failed for '\(shortcut.title, privacy: .private)'")
```

### Prompt

> In `KeyMinder/Scraping/MenuScraper.swift`, find the two `Logger.scraper.info` calls
> inside `collectGroups(in:includeAll:)` and `collectShortcutsFlat(in:includeAll:depth:)`
> that log empty-submenu diagnostics (both match the pattern
> `"… yielded 0 items (… child items…)"`). In each call, change the `title` interpolation
> from `privacy: .public` to `privacy: .private`, and change the `hint` interpolation from
> `privacy: .public` to `privacy: .private`. Leave `itemCount` as `.public` (it is an
> integer count, not user-identifying content).
>
> In `KeyMinder/Accessibility/ShortcutActivator.swift`, find the
> `Logger.accessibility.error` call and change the `shortcut.title` interpolation from
> `privacy: .public` to `privacy: .private`.
>
> Do not change any other log statements or any non-log code.

---

## Fix 3 — F-NEW-1 (Low): Add depth limit to recursive AX submenu traversal

### What
`MenuScraper.collectShortcutsFlat` recurses into sub-submenus without a depth bound:

```swift
if let submenu {
    let sub = collectShortcutsFlat(in: submenu, includeAll: includeAll)
    ...
}
```

A malicious or misbehaving app could return an arbitrarily deep AX menu hierarchy. Without
a bound, the scrape task (a `Task.detached`) could exhaust its stack and crash KeyMinder,
or block for many seconds while AX timeouts accumulate across hundreds of recursive calls.

Adding a `depth` parameter and bailing at 10 is well above the deepest real menu hierarchy
(typically 3–4 levels) and caps both stack consumption and per-scrape latency.

### Why it is safe
No shipping macOS app has menus deeper than five or six levels. A limit of 10 will never
trim real content. The change only affects `collectShortcutsFlat`; `collectGroups` is
unchanged because it only recurses one level into submenus by calling
`collectShortcutsFlat`, and that one call now carries the depth counter.

### File changed

**`KeyMinder/Scraping/MenuScraper.swift` — `collectShortcutsFlat` signature and recursive call site**

```swift
// BEFORE
private static func collectShortcutsFlat(in menu: AXUIElement, includeAll: Bool = false) -> [Shortcut] {
    var result: [Shortcut] = []
    for item in children(menu) {
        ...
        if let submenu {
            let sub = collectShortcutsFlat(in: submenu, includeAll: includeAll)
            ...
            result.append(contentsOf: sub)
        }
    }
    return result
}

// AFTER
private static func collectShortcutsFlat(
    in menu: AXUIElement, includeAll: Bool = false, depth: Int = 0
) -> [Shortcut] {
    guard depth < 10 else { return [] }
    var result: [Shortcut] = []
    for item in children(menu) {
        ...
        if let submenu {
            let sub = collectShortcutsFlat(in: submenu, includeAll: includeAll, depth: depth + 1)
            ...
            result.append(contentsOf: sub)
        }
    }
    return result
}
```

### Prompt

> In `KeyMinder/Scraping/MenuScraper.swift`, modify the private static method
> `collectShortcutsFlat(in:includeAll:)` as follows:
>
> 1. Add a third parameter `depth: Int = 0` to the signature, after `includeAll`.
> 2. Insert `guard depth < 10 else { return [] }` as the first line of the method body,
>    before the `var result` declaration.
> 3. In the recursive call to `collectShortcutsFlat` inside the `if let submenu` block,
>    add `depth: depth + 1` as a trailing argument.
>
> The call site in `collectGroups(in:includeAll:)` that calls `collectShortcutsFlat` does
> not pass a `depth` argument and must be left unchanged — it will use the default value
> of `0`. No other changes.

---

## Fix 4 — F-04 (Informational): Add explicit `privacy: .private` annotation on error log

### What
`SettingsView.swift` logs `error.localizedDescription` without a `privacy:` annotation.
Swift's `os.Logger` defaults dynamic strings to `.private` (redacted in collected logs),
so this is already safe — but the absence of an explicit annotation is a maintenance trap:
a future editor might add `.public` without realising the string can contain system error
text. Making the intent explicit costs one word.

### Why it is safe
A pure annotation change on a log statement. No effect on runtime behaviour or the UI.

### File changed

**`KeyMinder/UI/Settings/SettingsView.swift` — login-item error log**

```swift
// BEFORE
Logger.settings.error("Login item toggle failed: \(error.localizedDescription)")

// AFTER
Logger.settings.error("Login item toggle failed: \(error.localizedDescription, privacy: .private)")
```

### Prompt

> In `KeyMinder/UI/Settings/SettingsView.swift`, find the `Logger.settings.error` call
> inside the `launchAtLogin` `didSet` observer. It currently reads
> `"Login item toggle failed: \(error.localizedDescription)"`. Add `privacy: .private`
> to the interpolation so it reads `\(error.localizedDescription, privacy: .private)`.
> No other changes.

---

## Fix 5 — F-07 (Informational): Document the global key-event monitor scope

### What
`PopupController.installDismissalMonitors()` registers a global `keyDown` monitor so it
can intercept Esc. The callback receives **all** system-wide keyDown events while the
popup is visible, but only acts on key code 53. A future developer unfamiliar with
`addGlobalMonitorForEvents` might widen the handler without realising the full scope of
what it receives. A security comment makes the contract explicit.

### Why it is safe
Comment-only change.

### File changed

**`KeyMinder/UI/Popup/PopupController.swift` — above the global keyDown monitor**

```swift
// BEFORE
        // Esc while frontmost (works because we have Accessibility permission).
        // Used when the panel isn't key; same clear-then-dismiss semantics.
        if let globalKey = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in if event.keyCode == 53 { _ = self?.handleEscape() } }
        ) {

// AFTER
        // Esc while frontmost (works because we have Accessibility permission).
        // Used when the panel isn't key; same clear-then-dismiss semantics.
        // Security: this callback receives ALL system-wide keyDown events while the popup
        // is visible. Only keyCode 53 (Esc) must ever be acted upon here — do not log,
        // store, or forward any other key event data.
        if let globalKey = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in if event.keyCode == 53 { _ = self?.handleEscape() } }
        ) {
```

### Prompt

> In `KeyMinder/UI/Popup/PopupController.swift`, find the two-line comment block
> `// Esc while frontmost …` / `// Used when the panel isn't key …` that immediately
> precedes the `NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], …)` call inside
> `installDismissalMonitors()`. After those two existing comment lines, and before the
> `if let globalKey =` line, insert exactly these two lines:
> ```swift
>         // Security: this callback receives ALL system-wide keyDown events while the popup
>         // is visible. Only keyCode 53 (Esc) must ever be acted upon here — do not log,
>         // store, or forward any other key event data.
> ```
> No other changes.

---

## Fix 6 — F-05 (Informational): Set Release signing identity to `Developer ID Application`

### What
The Release build configuration for the main KeyMinder target has
`CODE_SIGN_IDENTITY = "Apple Development"`. An archive built with that identity cannot be
notarized. Switching the Release config to `"Developer ID Application"` means Xcode
automatic signing selects the correct certificate when archiving for distribution,
eliminating a silent footgun for any contributor who builds a release package.

The Debug configuration intentionally keeps `"Apple Development"` — local development
runs do not need a Developer ID cert.

### Why it is safe
`CODE_SIGN_IDENTITY` under `CODE_SIGN_STYLE = Automatic` is a preference hint; if the
specified identity is absent from the keychain, Xcode falls back automatically. During
day-to-day development (Debug builds) this setting is not used. For Release archives it
ensures the correct cert is chosen without a manual step.

### File changed

**`KeyMinder.xcodeproj/project.pbxproj` — Release config block UUID `3E3EC5A646DA464EBE9375A9`**

```
/* BEFORE — Release block only */
CODE_SIGN_IDENTITY = "Apple Development";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";

/* AFTER — Release block only */
CODE_SIGN_IDENTITY = "Developer ID Application";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Developer ID Application";
```

### Prompt

> In `KeyMinder.xcodeproj/project.pbxproj`, find the `XCBuildConfiguration` section
> block with UUID `3E3EC5A646DA464EBE9375A9`. It has `name = Release` and contains
> `INFOPLIST_KEY_LSUIElement = YES`. Change both `CODE_SIGN_IDENTITY` lines in that block
> from `"Apple Development"` to `"Developer ID Application"`. Do not touch any other
> build configuration block (the Debug block UUID `AD0EF6C9F04242308A16E75B` and both
> test-target blocks must be left exactly as they are).

---

## Application order

Apply in this sequence to keep each diff reviewable in isolation:

1. **Fix 1** (force cast) — one-line change in a single helper; easiest to verify correct.
2. **Fix 3** (recursion depth) — adds one guard and one argument; verify with tests.
3. **Fix 2** (log privacy: titles) — three one-word changes across two files; confirm tests still pass.
4. **Fix 4** (log privacy: annotation) — one-word change; can be in the same commit as Fix 2.
5. **Fix 5** (security comment) — comment-only; can be in the same commit as Fix 4.
6. **Fix 6** (project.pbxproj) — separate commit; infrastructure change, noisier diff.

Suggested commit messages:
- Fixes 1–5: `fix: tighten AX safety, log privacy, and recursion depth`
- Fix 6: `fix: use Developer ID signing identity for Release builds`

---

## Verification

After applying all fixes:

1. Run `xcodebuild test` — all existing tests must pass (no logic changed).
2. Build and run the app; open KeyMinder for at least two different target apps and confirm shortcuts appear normally.
3. Verify live logging still shows human-readable output (live stream is not redacted):
   ```
   /usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder'"
   ```
   Trigger a few popup opens; submenu names should now appear as `<private>` in a
   collected archive but remain readable in the live stream.
4. To confirm the recursion fix specifically: open KeyMinder against an app with deep
   submenus (e.g. Finder's "Open With") and confirm no crash.
5. After Fix 6: archive → Distribute App → Direct Distribution → confirm Xcode selects
   "Developer ID Application" automatically without prompting for a cert choice.
