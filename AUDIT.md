# KeyMinder — Security Audit

**Date:** 2026-06-07
**Auditor:** Claude Sonnet 4.6 (automated static analysis)
**Scope:** Full project, current HEAD (v0.1.79, branch `main`)
**Prior audit:** `Claude/AUDIT_2026-06-01.md` (v0.1.39). Status of all prior findings is tracked explicitly in each section.

---

## 1. Project Reconnaissance

### Purpose & entry points

KeyMinder is a macOS menu-bar agent that reads the frontmost app's menus via the Accessibility API and displays keyboard shortcuts in a floating popup. It also shows system-wide shortcuts by querying the Window Server.

**Entry points:**
- `KeyMinderApp.swift` (`@main`) — delegates immediately to `AppDelegate`
- `AppDelegate.swift` — status-bar icon (left/right click), global hotkey via Carbon `RegisterEventHotKey`, double-tap modifier via `NSEvent.addGlobalMonitorForEvents`
- `MenuScraper.swift` — parses AX attribute strings returned by arbitrary third-party apps
- `SystemShortcutsProvider.swift` — reads user plist files and calls private CGS APIs via `dlopen`/`dlsym`

**Privilege level:** Standard user. No admin rights required. Requires the TCC Accessibility permission (`AXIsProcessTrusted()`) to read other apps' menus. This grant is scoped to `org.afaik.KeyMinder` and is identity-anchored to the signing certificate.

### Entitlements

No `.entitlements` file exists. No `com.apple.security.*` keys are set. This is correct for non-sandboxed Developer ID distribution — App Sandbox cannot coexist with cross-process Accessibility API reads.

### Info.plist security-relevant keys

| Key | Value | Notes |
|-----|-------|-------|
| `LSUIElement` | `YES` | Agent app — no Dock icon, no main menu bar. Correct. |
| `NSAppTransportSecurity` | (absent) | No network stack. No ATS config needed. ✓ |
| `CFBundleURLSchemes` | (absent) | No URL scheme handler. ✓ |
| `NSAppleEventsUsageDescription` | (absent) | No AppleScript/AppleEvents surface. ✓ |

### Code signing

| Config | `ENABLE_HARDENED_RUNTIME` | `CODE_SIGN_IDENTITY` | Status |
|--------|--------------------------|----------------------|--------|
| Debug | YES | `"Apple Development"` | Correct for local dev |
| Release | YES | **`"Apple Development"`** | ⚠ Should be `"Developer ID Application"` (F-05, *still open*) |

No runtime exceptions in Hardened Runtime (no JIT, no unsigned executable memory, no DYLD environment variable overrides). ✓

---

## 2. Dependency Audit

**Zero third-party dependencies.** The project uses only Apple system frameworks:

| Framework | Purpose |
|-----------|---------|
| AppKit / SwiftUI | UI |
| ApplicationServices | Accessibility API (`AXUIElement*`) |
| Carbon.HIToolbox | Global hotkey (`RegisterEventHotKey`) |
| CoreGraphics | Private CGS APIs via `dlopen`/`dlsym` (new since v0.1.39) |
| ServiceManagement | Login item (`SMAppService`) |
| os | Unified logging (`Logger`) |
| Darwin | `dlopen`, `dlsym` for private CGS symbol resolution |

No SPM `Package.swift`, Podfile, or Cartfile. No binary blobs, pre-built XCFrameworks, or vendored `.a`/`.dylib` files.

**CVE exposure:** None — no third-party libraries to audit.

**Auto-updater:** None. No Sparkle or similar framework. No code is downloaded or executed at runtime.

---

## 3. Sensitive Data & Secrets

### Hardcoded credentials

None found.

### `.env` file

`scripts/.env` contains `TEAM_ID=R4J8ZNC9HF`. This file is listed in `.gitignore` (`scripts/.env`) and is correctly excluded from version control. ✓

**However:** `CLAUDE.md` (line 38) and `Claude/AUDIT_2026-06-01.md` both contain the literal team ID and are checked into the repository. Apple Developer Team IDs are embedded in distributed app bundles and are not a secret — they are publicly visible via `codesign -dv`. This is informational only.

### UserDefaults contents

- `globalHotkey` — JSON-encoded `GlobalHotkey` struct (`keyCode: UInt32`, `carbonModifiers: UInt32`, `displayString: String`). No sensitive data.
- `keyAccentColor` — `NSKeyedArchiver`-serialised `NSColor`. No sensitive data.
- `ignoreList` — JSON blob of user-defined command/app titles. No sensitive data.
- All other keys: booleans and strings. No sensitive data.

Deserialisation uses:
- `JSONDecoder().decode(GlobalHotkey.self, from: data)` — typed decode; no code execution path from tampered values.
- `NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)` — class-restricted decode with `requiringSecureCoding: true`. ✓

### Keychain

Not used. Correct — no credentials to store.

### Log privacy

**Prior finding F-02 (Medium) — FIXED since v0.1.39.** All log calls that previously emitted third-party menu content as `.public` now use `privacy: .private`:
- `MenuScraper.swift:93` — submenu title: `.private` ✓
- `MenuScraper.swift:138` — nested submenu title: `.private` ✓
- `ShortcutActivator.swift:18` — shortcut title: `.private` ✓

**Prior finding F-04 (Informational) — FIXED.** `SettingsView.swift` login-item error log now uses `privacy: .private` explicitly. ✓

Three log calls in `DoubleTapTrigger.swift` emit modifier-flag raw values as `.public` (e.g., `0x100000`). These are bitmasks of modifier keys only (⌘/⌥/⌃/⇧); they do not reveal typed characters. ✓

---

## 4. Inter-Process Communication & Attack Surface

| Mechanism | Present | Notes |
|-----------|---------|-------|
| XPC services | No | — |
| NSXPCConnection | No | — |
| Distributed Objects | No | — |
| Mach ports (explicit) | No | — |
| CGEventTap | **No** | Removed since prior audit; replaced by NSEvent monitors |
| Unix sockets | No | — |
| URL schemes | No | — |
| AppleEvents | No | — |
| Privileged helpers (SMJobBless) | No | — |
| Carbon global hotkey | Yes | `RegisterEventHotKey` — activates popup on hotkey press |
| NSEvent global monitor (`.flagsChanged`) | Yes | `DoubleTapTrigger` + `PopupController` — modifier key state only |
| NSEvent global monitor (`.keyDown`) | Yes | `DoubleTapTrigger` (state reset) + `PopupController` (Esc only) |
| NSEvent local monitor (`.keyDown`) | Yes | `SettingsModel` recording; `PopupController` Tab/Return navigation |
| AX cross-process read | Yes | `AXUIElementCopyAttributeValue` — reads menu structure |
| AX cross-process action | Yes | `AXUIElementPerformAction(kAXPressAction)` — user-initiated only |
| Private CGS API | Yes | `SystemShortcutsProvider` — `dlopen`/`dlsym` into CoreGraphics |

### NSEvent global `.keyDown` monitor (PopupController)

`PopupController.swift:385-390` registers a global `.keyDown` monitor while the popup is visible. This callback receives **all system-wide keyDown events** while the popup is open, including from sensitive apps (e.g., password managers typing into other fields).

**Prior finding F-07 (Informational) — FIXED.** A security comment is now in place at `PopupController.swift:382-384` documenting that only `keyCode == 53` (Esc) is acted upon and that no other key content is logged, stored, or forwarded. ✓

The implementation correctly limits action to keyCode 53, and the narrow time window (popup visible) limits exposure.

### Private CGS API (`SystemShortcutsProvider`) — **NEW since v0.1.39**

**Finding N-01 (Low)** `SystemShortcutsProvider.swift:6-24`

The file uses `dlopen`/`dlsym` to resolve three undocumented CoreGraphics symbols at module-init time, then casts them via `unsafeBitCast` to typed function pointers:

```swift
private let _cgsMainConnFn: _CGSMainConnFn? = _cgsHandle
    .flatMap { dlsym($0, "CGSMainConnectionID") }
    .map { unsafeBitCast($0, to: _CGSMainConnFn.self) }
```

The code correctly falls back (`return nil`) when any symbol is absent, which handles the case where Apple removes these functions in a future macOS version. **However, `unsafeBitCast` provides no protection against a signature change**: if Apple changes the parameters or return type of any of these three functions (e.g., adding a parameter or widening a type), calling the resulting function pointer passes arguments in the wrong registers, causing undefined behavior — in practice, a crash or silent data corruption. This would not be caught at build time and would not produce a nil function pointer.

The three private symbols and their assumed signatures:
- `CGSMainConnectionID()` → `Int32`
- `CGSGetSymbolicHotKeyValue(Int32, Int32, *UInt16, *UInt32)` → `OSStatus`
- `CGSIsSymbolicHotKeyEnabled(Int32, Int32)` → `Bool`

These have been stable across many macOS releases, but their stability is not guaranteed by Apple.

**Remediation:** Add a maximum macOS version check (e.g., cap CGS use to macOS 15.x) and fall back to plist parsing for untested versions. Document which macOS versions were validated. Consider filing a Feedback Assistant request for a public API alternative.

### AX cross-process action (`ShortcutActivator`)

`AXUIElementPerformAction(element, kAXPressAction)` executes a menu item in the target app. This is only triggered by explicit user interaction (click or Return key). If the target app exits between scrape and activation, the AX call fails gracefully. PID recycling risk is negligible — a frontmost-app change dismisses the popup before any other app can claim the PID. ✓

---

## 5. Data Handling

### Shell / process execution

None in the app code. No `Process`, `NSTask`, or shell invocation anywhere in `KeyMinder/`. ✓

The release scripts (`scripts/`) use shell extensively but are developer-only tooling, not part of the shipped app. The `VERSION` variable is derived from `project.pbxproj` via `grep`/`sed` and is used in path construction and echo statements. No user-supplied input reaches shell commands. ✓

### File I/O

`SystemShortcutsProvider` reads two plist files from `~/Library/Preferences/`:
- `com.apple.symbolichotkeys.plist` — system shortcut configuration
- `.GlobalPreferences.plist` — global preferences including `NSUserKeyEquivalents`

Both are read with `Data(contentsOf:)` + `PropertyListSerialization`, which cannot execute code. Data is only used for display in the popup, never written to disk or transmitted over a network. The read is opportunistic — failure is silently ignored with fallback to bundled defaults. ✓

**Note:** `.GlobalPreferences.plist` can contain sensitive data from other apps (historically, some apps stored credentials here). KeyMinder reads only the `NSUserKeyEquivalents` key, limiting the blast radius if parsing is somehow exploited. ✓

### Unsafe Swift (`Unmanaged`, raw pointers)

**`HotkeyManager.swift:74`** — `Unmanaged.passUnretained(self).toOpaque()` for the Carbon event handler `userData` context. Correct: `passUnretained` is appropriate because Carbon does not take ownership; the singleton outlives the callback. `takeUnretainedValue()` is used on the receiving side — no retain/release imbalance. ✓

**`SystemShortcutsProvider.swift:14-24`** — `unsafeBitCast` on `dlsym` results (see N-01 above).

### Force cast (`as!`)

**Prior finding F-01 (Low) — still open.** `MenuScraper.swift:161`:

```swift
return (raw as! AXUIElement)
```

The surrounding `CFGetTypeID` guard makes this crash-impossible in normal operation. The return type is already `AXUIElement?`, so `as?` would be behaviour-equivalent. The force cast is the only `as!` in the codebase.

**Finding N-02 (Informational)** `SystemShortcutsProvider.swift:260`:

```swift
? String(UnicodeScalar(keyChar)!) : nil
```

The ternary guard `keyChar >= 0x20 && keyChar <= 0x7E` ensures only valid printable ASCII scalars reach this line, making the force-unwrap safe. However, if the guard condition were relaxed in a future edit, the crash is silent. Prefer `UnicodeScalar(keyChar).map { String($0) }`.

**Finding N-03 (Informational)** `PopupRootView.swift:354`:

```swift
let ch = item.glyph.first!
```

`mods` is a compile-time constant with non-empty strings (`"⌃"`, `"⌥"`, `"⇧"`, `"⌘"`). `.first` will never be nil. Safe but a code smell if the constant is ever extended with an empty string.

**Finding N-04 (Informational)** `SettingsView.swift:505-506, 656`:

```swift
.filter { ... && $0.bundleIdentifier != nil && $0.localizedName != nil }
.filter { IgnoreListStore.shared.ignoredApps[$0.bundleIdentifier!] == nil }
.map { (bundleID: $0.bundleIdentifier!, name: $0.localizedName!) }
```

The nil checks in the first filter guard the force unwraps in subsequent closures. `Array.filter` + `.map` on `Array` is strict (not lazy), so the ordering is safe. However, the two-step pattern (nil-check in filter, force-unwrap in map) is fragile if the chain is ever refactored.

### Recursive AX traversal depth limit

**Prior finding F-NEW-1 (Low) — FIXED.** `MenuScraper.collectShortcutsFlat` now has a `depth: Int = 0` parameter with `guard depth < 10 else { return [] }`. ✓

### UserDefaults tamper

A local attacker with filesystem access could modify `~/Library/Preferences/org.afaik.KeyMinder.plist`. The hotkey value is decoded via `JSONDecoder` into a typed struct with only `UInt32` and `String` fields — no code-execution path from tampered values. The ignore list is decoded via `JSONDecoder` into typed `[String]` arrays. Worst outcome is a changed hotkey or altered ignore list. Out-of-scope (attacker already has local file access). Informational only.

---

## 6. Network & TLS

**No network calls exist.** No `URLSession`, `URLRequest`, `Network.framework`, `CFNetwork`, `WKWebView`, or third-party HTTP library is imported or used anywhere in `KeyMinder/`. No data is transmitted over any network. No ATS configuration is needed or present.

`AppDelegate.swift:249` constructs a `URL` for the About panel link (`https://donald.van-de-weyer.net/keyminder.html`), but this URL is only passed to `NSApp.orderFrontStandardAboutPanel` and never opened programmatically. `NSWorkspace.shared.open(url)` is called only with the `x-apple.systempreferences:` scheme (in `AccessibilityPermission.openSettings()`), which opens System Settings — not a network request.

This section has **no actionable findings**.

---

## 7. Update & Distribution Mechanism

**No auto-updater.** No Sparkle, Squirrel, or custom update mechanism. Users update manually by downloading from the project website.

**Distribution path:** Developer ID + Hardened Runtime + `xcrun notarytool` (documented in `CLAUDE.md` and `scripts/release.sh`). Hardened Runtime is correctly enabled on both Debug and Release configs. ✓

**Prior finding F-05 (Informational) — still open.** The Release build configuration (`3E3EC5A646DA464EBE9375A9`) has:

```
CODE_SIGN_IDENTITY = "Apple Development";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
```

`release.sh` uses `-exportArchive` with `ExportOptions.plist` specifying `method = developer-id`, which causes `xcodebuild` to re-sign with the Developer ID cert during export regardless of the project's `CODE_SIGN_IDENTITY`. As a result, notarization succeeds in practice. However, the Release config's identity is misleading and could break if the export step is skipped. The Release config should explicitly declare `"Developer ID Application"`.

---

## 8. Code Quality Red Flags

### Force unwraps on security paths

No force unwraps on auth results, crypto outputs, or AX error returns. The four `!` instances documented under Section 5 are all in UI or data-parsing code with surrounding guards. None is on a security-critical path.

### `#if DEBUG` security bypasses

None found. ✓

### Security-relevant TODOs / FIXMEs

None found. ✓

### Deprecated / insecure APIs

- `Carbon.HIToolbox` (`RegisterEventHotKey`) — legacy but the only reliable cross-process global hotkey API on macOS without sandboxing. No modern replacement exists. Acceptable.
- `dlopen`/`dlsym`/`unsafeBitCast` for private CGS APIs — not deprecated, but undocumented and carries signature-stability risk (N-01).
- No MD5, SHA-1, DES, or other broken cryptographic primitives. ✓
- No `SecKeychainFind*` (deprecated keychain APIs). ✓

### AX timeout

`AXUIElementSetMessagingTimeout(app, 1.0)` is applied before any attribute reads, preventing a hung target app from blocking the scrape task indefinitely. ✓

### Concurrency

`@MainActor` is used consistently for all UI and singleton state. The detached scrape task receives only value types (`pid_t`, `String`, `Set<String>`) from the main actor — no shared mutable state crosses isolation boundaries. The draining pattern (awaiting the previous `detachedScrapeTask` before starting a new traversal) correctly serialises access to the AX IPC, which has no Swift cancellation checkpoints. ✓

---

## Summary Table

| Area | Critical | High | Medium | Low | Informational |
|------|----------|------|--------|-----|---------------|
| 1. Reconnaissance | — | — | — | — | F-05 *(open)*, TEAM_ID in CLAUDE.md |
| 2. Dependencies | — | — | — | — | — |
| 3. Sensitive Data / Secrets | — | — | — | — | F-02 ✓, F-04 ✓ |
| 4. IPC & Attack Surface | — | — | — | N-01 (CGS sig mismatch) | F-07 ✓ |
| 5. Data Handling | — | — | — | F-01 *(open)*, F-NEW-1 ✓ | N-02, N-03, N-04 |
| 6. Network & TLS | — | — | — | — | — |
| 7. Update & Distribution | — | — | — | — | F-05 *(open)* |
| 8. Code Quality | — | — | — | — | — |
| **Total (open)** | **0** | **0** | **0** | **2** | **3** |

**Legend:** ✓ = fixed since prior audit | *(open)* = carried over from prior audit

Prior findings closed since v0.1.39: F-02 (Medium), F-04, F-07, F-NEW-1.
New findings since v0.1.39: N-01 (Low), N-02, N-03, N-04 (all Informational).

---

## Top-5 Prioritised Remediation List

### 1. N-01 — Private CGS function-signature mismatch (Low)
**File:** `KeyMinder/Scraping/SystemShortcutsProvider.swift:14-24`

Add a maximum macOS version guard so the CGS path is bypassed on untested future OS versions, falling back to the existing plist parser:

```swift
private static func loadViaCGS() -> [Int: (keys: String, isDisabled: Bool)]? {
    // Cap to tested macOS versions; fall back to plist parser on future OS.
    guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion <= 15 else {
        return nil
    }
    guard let mainConnFn = _cgsMainConnFn, ... else { return nil }
    ...
}
```

Update the cap with each new major macOS release after re-verifying the three function signatures. This eliminates the silent undefined-behaviour risk on an OS version where Apple changes these signatures.

### 2. F-01 — Force cast `as! AXUIElement` (Low)
**File:** `KeyMinder/Scraping/MenuScraper.swift:161`

Replace the force cast with a conditional cast. The `CFGetTypeID` guard above makes this safe in all realistic cases, but `as?` eliminates the crash path entirely and matches the optional return type:

```swift
// Before
return (raw as! AXUIElement)
// After
return raw as? AXUIElement
```

### 3. F-05 — Release config signing identity (Informational)
**File:** `KeyMinder.xcodeproj/project.pbxproj`, UUID `3E3EC5A646DA464EBE9375A9` (Release config)

Change both `CODE_SIGN_IDENTITY` lines from `"Apple Development"` to `"Developer ID Application"`. The release script's export step currently compensates for this, but the project config should match the intended distribution identity to avoid confusion and potential breakage if the export step is ever skipped.

### 4. N-02 — Force unwrap on guarded UnicodeScalar (Informational)
**File:** `KeyMinder/Scraping/SystemShortcutsProvider.swift:260`

```swift
// Before
? String(UnicodeScalar(keyChar)!) : nil
// After
UnicodeScalar(keyChar).map { String($0) }
```

Eliminates the `!` and makes the nil-on-invalid-scalar path explicit.

### 5. N-03/N-04 — Force unwraps after nil-check guards (Informational)
**Files:** `KeyMinder/UI/Popup/PopupRootView.swift:354`, `KeyMinder/UI/Settings/SettingsView.swift:505-506, 656`

For `PopupRootView.swift:354`, the `mods` constant has non-empty strings, so `.first` is always non-nil. This is safe but can be made explicit with `item.glyph.first ?? "?"`.

For `SettingsView.swift:505-506, 656`, collapse the nil-check filter and force-unwrap map into a single `compactMap` to make the intent self-documenting:

```swift
// Before
.filter { ... && $0.bundleIdentifier != nil && $0.localizedName != nil }
.map { (bundleID: $0.bundleIdentifier!, name: $0.localizedName!) }
// After
.compactMap { app -> (bundleID: String, name: String)? in
    guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
    return (bundleID: id, name: name)
}
```

---

## Areas Where Review Could Not Be Completed

| Area | Limitation | Recommended manual step |
|------|-----------|------------------------|
| Build artifact integrity | No built binary available to inspect | After each release: `codesign -dv --verbose=4 KeyMinder.app` and `spctl --assess --type execute KeyMinder.app` |
| TCC grant scope | Cannot read `/Library/Application Support/com.apple.TCC/TCC.db` | Verify the Accessibility grant is scoped to `org.afaik.KeyMinder` only |
| CGS function signatures | Static analysis only; actual signatures verified by reading Apple's private headers, not source | Run KeyMinder on each new macOS beta and check `systemshortcutsprovider` log output; update the version cap in N-01 remediation |
| Runtime AX data | Cannot observe live AX IPC | Run `log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder'"` while targeting a password manager to confirm no sensitive data leaks |
| CVE scanning | No third-party dependencies to scan | N/A — re-run if dependencies are added |
| Fuzzing AX inputs | No dynamic testing | Build a minimal macOS app with 100+ levels of nested `NSMenu` to confirm the depth-10 limit holds |

---

*This document covers a specific point-in-time snapshot (v0.1.79, commit `692b006`). Re-run the audit when significant new features are added — especially any that introduce network calls, XPC services, or new IPC mechanisms.*
