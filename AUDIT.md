# KeyMinder — Security Audit

**Date:** 2026-06-07 (last updated 2026-07-02 after the pre-distribution audit at v1.0.173)
**Auditor:** Claude Sonnet 4.6 (automated static analysis); 2026-07-02 pass by Claude Fable 5
**Scope:** Full project, audited at v0.1.79; all findings resolved by v0.1.83 except where noted; Sparkle sections updated at v0.1.90; pre-distribution security audit 2026-07-02 at v1.0.173 (findings SEC-01…SEC-05, fixes landed in v1.0.174)
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

*(Updated 2026-07-02 — SEC-03.)* `KeyMinder/KeyMinder.entitlements` exists and is wired into both build configurations via `CODE_SIGN_ENTITLEMENTS`. It contains exactly one entitlement:

| Entitlement | Value | Justification |
|-------------|-------|---------------|
| `com.apple.developer.ubiquity-kvstore-identifier` | `$(TeamIdentifierPrefix)org.afaik.KeyMinder` | iCloud Key-Value Store for the opt-in settings sync (`SettingsSync`). Scoped to KeyMinder's own container only. |

No `com.apple.security.*` keys are set — the app remains non-sandboxed with **zero Hardened Runtime exceptions**, which is correct for Developer ID distribution (App Sandbox cannot coexist with cross-process Accessibility API reads).

### Info.plist security-relevant keys

| Key | Value | Notes |
|-----|-------|-------|
| `LSUIElement` | `YES` | Agent app — no Dock icon, no main menu bar. Correct. |
| `NSAppTransportSecurity` | (absent) | No app-code network stack. Sparkle (bundled framework) fetches the appcast over HTTPS; ATS applies to it automatically. ✓ |
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

**One third-party dependency:** Sparkle 2.9.2 (SPM, `https://github.com/sparkle-project/Sparkle`). All other dependencies are Apple system frameworks:

| Framework / Library | Purpose |
|---------------------|---------|
| **Sparkle 2.9.2** | Auto-updater (`SPUStandardUpdaterController`) |
| AppKit / SwiftUI | UI |
| ApplicationServices | Accessibility API (`AXUIElement*`) |
| Carbon.HIToolbox | Global hotkey (`RegisterEventHotKey`) |
| CoreGraphics | Private CGS APIs via `dlopen`/`dlsym` (new since v0.1.39) |
| ServiceManagement | Login item (`SMAppService`) |
| os | Unified logging (`Logger`) |
| Darwin | `dlopen`, `dlsym` for private CGS symbol resolution |

No Podfile or Cartfile. No binary blobs, pre-built XCFrameworks, or vendored `.a`/`.dylib` files beyond the Sparkle XCFramework fetched by SPM.

**CVE exposure:** Sparkle 2.x uses Ed25519 signatures to verify update packages before installation; update feeds are fetched over HTTPS. The project pins Sparkle at 2.9.2 via `Package.resolved`. Review release notes on Sparkle version bumps.

**Auto-updater:** Sparkle 2.9.2 (added v0.1.84). `SPUStandardUpdaterController` is instantiated in `AppDelegate` with a custom `UpdaterDelegate` that suppresses Sparkle's own first-run permission dialog (v0.1.90) — the onboarding wizard handles this preference instead. The Ed25519 signing key lives in the macOS Keychain (never in the repo); the public key is embedded in `Info.plist → SUPublicEDKey`. Update packages are downloaded and verified by Sparkle before installation; no app code executes during the update process.

---

## 3. Sensitive Data & Secrets

### Hardcoded credentials

None found.

### `.env` file

`.env` contains `TEAM_ID=R4J8ZNC9HF`. This file has been moved outside the repo tree to `~/Documents/Development/.config/KeyMinder/scripts/.env` and is therefore never in version control. ✓

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

**Finding N-01 (Low) — FIXED in v0.1.81** `SystemShortcutsProvider.swift:6-24`

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

**Fix applied (v0.1.81):** `loadViaCGS()` now returns `nil` immediately when `ProcessInfo.processInfo.operatingSystemVersion.majorVersion > 15`, falling back to the plist parser on untested future macOS versions. Update the cap with each new major macOS release after re-verifying the three function signatures. ✓

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

**`NSUserKeyEquivalents` injection surface:** `.GlobalPreferences.plist` is a **multi-writer global preferences domain** — any same-user process can write to it with `defaults write -g NSUserKeyEquivalents …` with zero privilege and zero user interaction. A background process could therefore inject arbitrary menu-item title strings into KeyMinder's popup. **Mitigation:** `ScrapedStringPolicy.sanitize(_:)` is applied to all `NSUserKeyEquivalents` keys before they are stored as `Shortcut.title`, stripping C0/C1 controls, bidi overrides, and capping length. Exported Markdown is additionally escaped via `ShortcutExporter`.

**Third-party registry injection surface (SEC-01, Medium) — FIXED in v1.0.174.** `ThirdPartyShortcutRegistry` reads JSON registration files from `~/Library/Application Support/KeyMinder/Integrations/` — the same same-user-writable trust boundary as `NSUserKeyEquivalents`. The EXT-01 fix (v1.0.149) did not cover this channel: `title`, `keys`, `group`, and `appName` flowed unsanitized into the popup UI and Markdown export, allowing bidi/control-character spoofing and unbounded string/count memory abuse. **Fix (v1.0.174):** `ScrapedStringPolicy.sanitize(_:)` is now applied to all four fields in `section(from:)`, and shortcuts are capped at `maxShortcutsPerFile = 500` per registration file.

### iCloud settings sync (data leaves the machine — updated 2026-07-02, SEC-03)

The earlier claim that scraped data is "never written to disk or transmitted over a network" no longer holds unqualified. `SettingsSync` mirrors a curated allowlist of `UserDefaults` keys to `NSUbiquitousKeyValueStore` (iCloud KVS). Two synced keys — `ignoreList` and `pinnedShortcuts` — contain menu-item titles originally scraped from other apps via AX, so AX-derived strings now reach Apple's iCloud servers **when the user opts in**. Mitigating factors: sync is off by default (`iCloudSyncEnabled`, only started when true in `applicationDidFinishLaunching`), the data is user-curated settings (not raw scrape output), transport/storage encryption is Apple's, and the KVS container is scoped to KeyMinder's own bundle. Values pulled from KVS are written back to `UserDefaults` and then decoded through the same typed decoders documented in §3 (typed `JSONDecoder`, class-restricted `NSKeyedUnarchiver`), so tampered KVS data (compromised iCloud account) degrades to a settings change, not code execution.

### Unsafe Swift (`Unmanaged`, raw pointers)

**`HotkeyManager.swift:74`** — `Unmanaged.passUnretained(self).toOpaque()` for the Carbon event handler `userData` context. Correct: `passUnretained` is appropriate because Carbon does not take ownership; the singleton outlives the callback. `takeUnretainedValue()` is used on the receiving side — no retain/release imbalance. ✓

**`SystemShortcutsProvider.swift:14-24`** — `unsafeBitCast` on `dlsym` results (see N-01 above).

### Force cast (`as!`)

**Prior finding F-01 (Low) — FIXED in v0.1.81, updated in v0.1.83.** `MenuScraper.swift`

```swift
// v0.1.81: removed force cast
return raw as? AXUIElement
// v0.1.83: Xcode 26 rejects CF-type conditional casts (as? / as! both error);
// unsafeBitCast is safe because the CFGetTypeID guard above confirms the type.
return unsafeBitCast(raw, to: AXUIElement.self)
```

The `CFGetTypeID` guard makes the unsafe cast safe in practice. `unsafeBitCast` was adopted in v0.1.83 because Xcode 26 (Swift 5 / macOS 26 SDK) promotes "conditional downcast to CoreFoundation type will always succeed" from a warning to an error for both `as?` and `as!`. ✓

**Finding N-02 (Informational) — FIXED in v0.1.82.** `SystemShortcutsProvider.swift`

```swift
// Before
? String(UnicodeScalar(keyChar)!) : nil
// After
UnicodeScalar(keyChar).map { String($0) } : nil
```

The `!` is replaced with `map`, making the nil-on-invalid-scalar path explicit. ✓

**Finding N-03 (Informational) — FIXED in v0.1.82.** `PopupRootView.swift`

`mods` tuple `glyph` field changed from `String` to `Character`; `item.glyph.first!` removed entirely since no `.first` call is needed. ✓

**Finding N-04 (Informational) — FIXED in v0.1.82.** `SettingsView.swift`

Both `runningApps` computed properties collapsed from a nil-check filter + force-unwrap map into a single `compactMap` with a `guard let` binding. ✓

### Recursive AX traversal depth limit

**Prior finding F-NEW-1 (Low) — FIXED.** `MenuScraper.collectShortcutsFlat` now has a `depth: Int = 0` parameter with `guard depth < 10 else { return [] }`. ✓

### UserDefaults tamper

A local attacker with filesystem access could modify `~/Library/Preferences/org.afaik.KeyMinder.plist`. The hotkey value is decoded via `JSONDecoder` into a typed struct with only `UInt32` and `String` fields — no code-execution path from tampered values. The ignore list is decoded via `JSONDecoder` into typed `[String]` arrays. Worst outcome is a changed hotkey or altered ignore list. Out-of-scope (attacker already has local file access). Informational only.

---

## 6. Network & TLS

**No network calls exist in app code.** No `URLSession`, `URLRequest`, `Network.framework`, `CFNetwork`, `WKWebView`, or third-party HTTP library is imported or used anywhere in `KeyMinder/`. The bundled **Sparkle** framework does make network calls (appcast fetch over HTTPS) — this is covered in §7. No ATS configuration is needed for app code; Sparkle operates under the system's default ATS policy.

`AppDelegate.swift:249` constructs a `URL` for the About panel link (`https://donald.van-de-weyer.net/keyminder.html`), but this URL is only passed to `NSApp.orderFrontStandardAboutPanel` and never opened programmatically. `NSWorkspace.shared.open(url)` is called only with the `x-apple.systempreferences:` scheme (in `AccessibilityPermission.openSettings()`), which opens System Settings — not a network request.

This section has **no actionable findings**.

---

## 7. Update & Distribution Mechanism

**Auto-updater: Sparkle 2.9.2** (added v0.1.84). `SPUStandardUpdaterController` fetches `https://keyminder.app/appcast.xml` and verifies each update package with Ed25519 before installation. The signing key is stored in the macOS Keychain and never leaves the developer machine; the public key is embedded in `Info.plist → SUPublicEDKey`. No app code is involved in the download or verification — Sparkle handles this entirely. The "Check for Updates Automatically" user preference is written to `SUEnableAutomaticChecks` in `UserDefaults`; Sparkle reads this key directly.

**Distribution path:** Developer ID + Hardened Runtime + `xcrun notarytool` (documented in `CLAUDE.md` and `scripts/release.sh`). Hardened Runtime is correctly enabled on both Debug and Release configs. ✓

**Prior finding F-05 (Informational) — still open.** The Release build configuration (`3E3EC5A646DA464EBE9375A9`) has:

```
CODE_SIGN_IDENTITY = "Apple Development";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
```

`release.sh` uses `-exportArchive` with `ExportOptions.plist` specifying `method = developer-id`, which causes `xcodebuild` to re-sign with the Developer ID cert during export regardless of the project's `CODE_SIGN_IDENTITY`. As a result, notarization succeeds in practice. However, the Release config's identity is misleading and could break if the export step is skipped. The Release config should explicitly declare `"Developer ID Application"`.

### 2026-07-02 findings (SEC-02, SEC-04, SEC-05)

**SEC-02 (Medium) — FIXED in v1.0.174.** `scripts/setup-sparkle-tools.sh` installed `generate_appcast` / `sign_update` from Sparkle's mutable `releases/latest` with no version pin and no integrity check. These tools read the Ed25519 private key from the Keychain and produce the signatures every user's Sparkle install trusts — the most supply-chain-sensitive tooling in the pipeline (the app-side framework was already pinned via `Package.resolved`). **Fix:** the script now pins `SPARKLE_VERSION=2.9.2` and verifies the tarball against a hardcoded SHA-256 before extraction, failing with a non-zero exit on mismatch (both paths tested). The Sparkle tool binaries are only ad-hoc signed (`TeamIdentifier=not set`), so a `codesign` identity check is not possible — the hash is the integrity anchor. Keep `SPARKLE_VERSION` in sync with `Package.resolved` when upgrading, and recompute the hash from a manually downloaded tarball.

**SEC-04 (Low) — open.** No SHA-256 checksum is published on the website next to the DMG/ZIP download links. The Homebrew cask checksum is generated and synced automatically (`release.sh` → `update-tap.sh`, with a post-substitution verification guard), and Sparkle update ZIPs carry EdDSA signatures — but a first-time manual DMG download relies solely on notarization/Gatekeeper. `DMG_SHA256` is already computed in `release.sh`; inject it into the download page at deploy time.

**SEC-05 (Low) — open.** Sparkle 2 still honors a legacy `SUFeedURL` override written into the app's user-defaults domain (`defaults write org.afaik.KeyMinder SUFeedURL …` by any same-user process). Impact is bounded — EdDSA verification against the Info.plist key and Sparkle's no-downgrade rule still apply, and a local attacker at that level has broader options — but calling the updater's `clearFeedURLFromUserDefaults()` (verify exact API name against the pinned Sparkle version) once at startup closes it. No delegate `feedURLString` override exists in the code (verified).

**Notarization chain (verified sound, 2026-07-02):** `release.sh` runs zip → `notarytool submit --wait` → `stapler staple` → re-zip of the stapled app; the DMG is built from the stapled app and is itself notarized and stapled. `set -euo pipefail` makes each step fatal, and `stapler staple` acts as a backstop even if `notarytool` were ever to exit 0 on a rejected submission (no ticket exists to staple). The shipped ZIP, DMG, and appcast asset are all post-staple artifacts.

---

## 8. Code Quality Red Flags

### Force unwraps on security paths

No force unwraps on auth results, crypto outputs, or AX error returns. All four `!` instances documented under Section 5 have been resolved (v0.1.81–v0.1.82). No `as!` or `!` force-unwraps remain in the codebase. ✓

### `#if DEBUG` security bypasses

None found. ✓

### Security-relevant TODOs / FIXMEs

None found. ✓

### Deprecated / insecure APIs

- `Carbon.HIToolbox` (`RegisterEventHotKey`) — legacy but the only reliable cross-process global hotkey API on macOS without sandboxing. No modern replacement exists. Acceptable.
- `dlopen`/`dlsym`/`unsafeBitCast` for private CGS APIs — not deprecated, but undocumented and carries signature-stability risk (N-01, mitigated by macOS version cap in v0.1.81).
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
| 1. Reconnaissance | — | — | — | — | F-05 *(open)*, TEAM_ID in CLAUDE.md, SEC-03 ✓ v1.0.174 |
| 2. Dependencies | — | — | — | — | — |
| 3. Sensitive Data / Secrets | — | — | — | — | F-02 ✓, F-04 ✓ |
| 4. IPC & Attack Surface | — | — | — | N-01 ✓ v0.1.81 | F-07 ✓ |
| 5. Data Handling | — | — | EXT-01 ✓ v1.0.149, EXT-02 ✓ v1.0.149, SEC-01 ✓ v1.0.174 | F-01 ✓ v0.1.81/v0.1.83, F-NEW-1 ✓ | N-02 ✓, N-03 ✓, N-04 ✓ v0.1.82 |
| 6. Network & TLS | — | — | — | — | — |
| 7. Update & Distribution | — | — | EXT-03 ✓ v1.0.150, SEC-02 ✓ v1.0.174 | SEC-04 *(open)*, SEC-05 *(open)* | F-05 *(open)* |
| 8. Code Quality | — | — | — | — | — |
| **Total (open)** | **0** | **0** | **0** | **2** | **1** |

**Legend:** ✓ = fixed | *(open)* = still open

Prior findings closed since v0.1.39: F-02 (Medium), F-04, F-07, F-NEW-1.
New findings since v0.1.39: N-01 (Low, fixed v0.1.81), N-02/N-03/N-04 (Informational, fixed v0.1.82).
External adversarial review 2026-06-12 (v1.0.118 scope): EXT-01 (scraped-string spoofing, Medium, fixed v1.0.149), EXT-02 (Markdown export injection, Medium, fixed v1.0.151), EXT-03 (Sparkle downgrade floor absent, Medium, fixed v1.0.150). AX press re-read (EXT-04, Low) fixed v1.0.152.
Pre-distribution audit 2026-07-02 (v1.0.173 scope): SEC-01 (third-party registry unsanitized, Medium, fixed v1.0.174), SEC-02 (Sparkle tools unpinned, Medium, fixed v1.0.174), SEC-03 (stale audit claims: entitlements + iCloud data flow, Informational, fixed in this document), SEC-04 (no website SHA-256, Low, open), SEC-05 (legacy `SUFeedURL` defaults override, Low, open). The 2026-07-02 pass re-verified all previously fixed findings still in place; none regressed.
**Three findings remain open:** F-05 (Informational, Release config signing identity), SEC-04 (Low), SEC-05 (Low).

---

## Remediation Status

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| F-01 | Low | Force cast `as! AXUIElement` in `MenuScraper` | ✅ Fixed v0.1.81; `unsafeBitCast` in v0.1.83 (Xcode 26) |
| N-01 | Low | Private CGS API signature-mismatch risk | ✅ Fixed v0.1.81 (macOS version cap) |
| N-02 | Informational | `UnicodeScalar(keyChar)!` in `SystemShortcutsProvider` | ✅ Fixed v0.1.82 |
| N-03 | Informational | `item.glyph.first!` in `PopupRootView` | ✅ Fixed v0.1.82 |
| N-04 | Informational | Force-unwrap after nil-check filter in `SettingsView` | ✅ Fixed v0.1.82 |
| F-05 | Informational | Release config `CODE_SIGN_IDENTITY = "Apple Development"` | ⚠️ Open — no functional impact; export step compensates |
| EXT-01 | Medium | Scraped strings (AX titles, NSUserKeyEquivalents) unsanitized — bidi/control-char spoofing | ✅ Fixed v1.0.149 (`ScrapedStringPolicy`, applied in `MenuScraper` + `SystemShortcutsProvider`) |
| EXT-02 | Medium | Markdown export injection — no escaping in `ShortcutExporter`; `keySymbol` returned whole cmdChar | ✅ Fixed v1.0.151 (`md()` + `codeSpan()` in `ShortcutExporter`; `String(scalar)` in `ShortcutFormatter`) |
| EXT-03 | Medium | Sparkle appcast lacked `minimumAutoupdateVersion` floor — genuine old signed build replayable | ✅ Fixed v1.0.150 (floor added to all non-current items; `release.sh` maintains it going forward) |
| EXT-04 | Low | `ShortcutActivator` did not re-read `kAXEnabledAttribute` or title at press time | ✅ Fixed v1.0.152 (re-reads both; logs title mismatches; refuses disabled items) |
| SEC-01 | Medium | `ThirdPartyShortcutRegistry` bypassed `ScrapedStringPolicy` — same-user JSON files injected unsanitized strings into popup + export | ✅ Fixed v1.0.174 (sanitize `title`/`keys`/`group`/`appName`; 500-shortcut cap per file) |
| SEC-02 | Medium | `setup-sparkle-tools.sh` installed signing-adjacent Sparkle tools from unpinned `releases/latest` with no integrity check | ✅ Fixed v1.0.174 (pinned 2.9.2 + hardcoded SHA-256 verification, fail-closed) |
| SEC-03 | Informational | AUDIT.md stale: claimed no entitlements file and no data transmission — both outdated by iCloud KVS sync | ✅ Fixed 2026-07-02 (this document: §1 Entitlements, §5 iCloud settings sync) |
| SEC-04 | Low | No SHA-256 published on website next to DMG/ZIP download links | ⚠️ Open — inject `DMG_SHA256` into download page during `release.sh` deploy |
| SEC-05 | Low | Sparkle legacy `SUFeedURL` user-defaults override not cleared at startup | ⚠️ Open — call updater's `clearFeedURLFromUserDefaults()` on launch (verify API name for pinned Sparkle) |

### F-05 — Release config signing identity (Informational, open)
**File:** `KeyMinder.xcodeproj/project.pbxproj`, UUID `3E3EC5A646DA464EBE9375A9` (Release config)

Change both `CODE_SIGN_IDENTITY` lines from `"Apple Development"` to `"Developer ID Application"`. The release script's export step currently compensates for this, but the project config should match the intended distribution identity to avoid confusion and potential breakage if the export step is ever skipped.

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

*Audited at v0.1.79 (commit `692b006`); all findings resolved by v0.1.83 (commit `3d3e3a9`) except F-05. Pre-distribution security audit re-run 2026-07-02 at v1.0.173: all prior fixes re-verified in place (none regressed); SEC-01/SEC-02 fixed in v1.0.174; F-05, SEC-04, SEC-05 remain open. Re-run the audit when significant new features are added — especially any that introduce network calls, XPC services, or new IPC mechanisms. Update the CGS version cap in `SystemShortcutsProvider.loadViaCGS()` with each new major macOS release.*
