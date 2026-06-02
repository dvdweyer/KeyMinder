# Fix Double-Tap Trigger — 2026-06-02

## Outcome (v0.1.48, shipped 2026-06-02)

The phased CGEventTap fixes (v0.1.45–v0.1.47) all failed. Debug logging confirmed
the root cause: on macOS 15, `tapDisabledByUserInput` fires on virtually every
keypress — even for listen-only taps — and the CGEventTap port became unreliable
during the disable/re-enable cycle. The entire CGEventTap infrastructure was
replaced with `NSEvent.addGlobalMonitorForEvents` (`.flagsChanged` + `.keyDown`),
which runs on the main thread and is never disabled by the system. ~120 lines
removed; the state machine is unchanged. See `HOWTO_Fix_Double_Tap_Not_Working.md`
for the current diagnostic guide.

---

## Background (original plan)

`DoubleTapTrigger.swift` installed a `CGEventTap` to detect rapid double-presses of
a modifier key. The user reports it does not work reliably. The TCC/signing-identity
root cause is documented in `HOWTO_Fix_Double_Tap_Not_Working.md` and is a
prerequisite: the tap must successfully install at launch (confirmed by the log line
`DoubleTapTrigger: watching <modifier>`). This plan addresses the **code-level
reliability failures** that persist even after TCC is clean.

---

## Identified root causes

### Bug 1 — `tapDisabledByUserInput` is silently ignored  (HIGH severity)

`DoubleTapTrigger.handle()` handles `tapDisabledByTimeout` and re-enables the tap.
It does **not** handle `tapDisabledByUserInput`. On macOS 14, the system sends this
event type when it considers the tap to be causing input latency. The current `switch`
falls to `default: break` and the tap stays permanently disabled for the rest of the
session — silently, with no log entry.

**File:** `KeyMinder/Settings/DoubleTapTrigger.swift`, `handle(type:event:)` (~line 131)

---

### Bug 2 — Tap is never re-installed after Accessibility is granted at runtime  (HIGH severity)

`AppDelegate.setupDoubleTap()` runs once at `applicationDidFinishLaunching`. If the
user grants Accessibility permission while the app is running (the standard first-run
onboarding flow), the `onPermissionGranted` callback calls `presentPopup()` but does
**not** call `setupDoubleTap()` again. So for every user who grants access via the
onboarding screen, the double-tap trigger is dead until they quit-and-relaunch —
which almost nobody will think to do.

**Files:** `KeyMinder/AppDelegate.swift`, `setupDoubleTap()` (~line 47) and
`UI/Popup/PopupController.swift`, the `onPermissionGranted` callback chain

---

### Bug 3 — Tap is never re-installed after system sleep/wake  (MEDIUM severity)

On macOS, `CGEventTap`s can be silently invalidated when the system wakes from sleep
or when the user's session is locked and unlocked. The app never listens for
`NSWorkspace.didWakeNotification` or `NSWorkspace.screensDidWakeNotification`, so
the tap is not recreated after sleep. The user will notice the trigger stops working
after the Mac wakes.

**File:** `KeyMinder/AppDelegate.swift`

---

### Bug 4 — Event tap fires on the main run loop; head contention can distort timing  (LOW severity)

The event tap source is added to `CFRunLoopGetMain()`. The state machine uses
wall-clock `Date()` comparisons with a 500 ms window. If the main thread is briefly
busy (e.g., a SwiftUI layout pass during popup show/hide animation) when a
`flagsChanged` event arrives, the run-loop delivery is delayed, and the inter-tap
interval measured by the state machine does not reflect the user's actual timing.
On a loaded system this makes the 500 ms window effectively shorter and the trigger
less forgiving.

Moving the tap to a dedicated background run loop fixes this. All that changes is
where `CFRunLoopAddSource` is called; the `MainActor.assumeIsolated` call in the
callback already handles the final dispatch to the main actor safely.

**File:** `KeyMinder/Settings/DoubleTapTrigger.swift`, `installTap()` (~line 100)

---

## Phase plan

Tackle bugs in severity order. Each phase is a separate, reviewable commit.

---

### Phase 1 — Fix `tapDisabledByUserInput` (Bug 1)

**Effort:** Small, targeted, zero risk of regression.  
**Model:** claude-sonnet-4-6 | **Effort level:** low

**Prompt:**

> You are fixing a reliability bug in `KeyMinder/Settings/DoubleTapTrigger.swift`.
>
> **Problem**: `DoubleTapTrigger.handle(type:event:)` re-enables the CGEventTap when
> it receives `tapDisabledByTimeout`, but does NOT handle `tapDisabledByUserInput`.
> When macOS sends that event type (raw value 0xFFFFFFFD, Swift name
> `CGEventType.tapDisabledByUserInput`) the tap is permanently disabled for the rest
> of the session with no log entry.
>
> **Fix**:
> 1. Extend the guard block at the top of `handle(type:event:)` to also re-enable the
>    tap for `.tapDisabledByUserInput`. Use the same re-enable logic as the
>    existing `tapDisabledByTimeout` branch. Log at `.warning` with the message
>    `"DoubleTapTrigger: re-enabling tap after user-input disable"`.
> 2. Also add the event type to the event mask in `installTap()` so macOS knows we
>    want to receive it (include `CGEventType.tapDisabledByUserInput.rawValue` in the
>    mask bitmask — note: these special types may need to be added via their raw value
>    if the Swift enum case does not exist; verify at compile time).
>
> Do not change anything else in this file. Do not add new methods or properties.
>
> After the change, confirm the project still compiles with:
> ```
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
>   -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
>   -derivedDataPath /tmp/KeyMinder-build build 2>&1 | tail -20
> ```
> Bump the patch version in `project.pbxproj` (`MARKETING_VERSION`).

---

### Phase 2 — Re-arm after Accessibility grant + after sleep (Bugs 2 & 3)

**Effort:** Two small AppDelegate changes; no concurrency risk.  
**Model:** claude-sonnet-4-6 | **Effort level:** low-medium

**Prompt:**

> You are fixing two reliability bugs in `KeyMinder/AppDelegate.swift`.
>
> **Bug A — no re-arm after runtime Accessibility grant**
>
> `setupDoubleTap()` runs once at launch. The `PopupController.onPermissionGranted`
> callback fires when the user grants Accessibility while the app is already running
> (the first-run onboarding path). That callback currently calls only `presentPopup()`.
> Add a call to `setupDoubleTap()` at the end of the `onPermissionGranted` closure
> in `applicationDidFinishLaunching`. This ensures the event tap is installed the
> moment permission is available, without requiring a relaunch.
>
> **Bug B — no re-arm after sleep/wake**
>
> CGEventTaps are silently invalidated when the Mac wakes from sleep. Register for
> `NSWorkspace.didWakeNotification` in `applicationDidFinishLaunching` and call
> `setupDoubleTap()` from the notification handler (only when double-tap is enabled;
> `DoubleTapTrigger.shared.start(modifier:)` already handles stop-before-restart, so
> calling it again is safe).
>
> `setupDoubleTap()` is already `private`. Promote it to package-private (remove
> `private`, no explicit access modifier) so it can be called from the notification
> handler inline; or simply call the relevant DoubleTapTrigger methods directly in
> the handler — whichever is cleaner.
>
> Do not change any other files. Compile and check:
> ```
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
>   -project KeyMinder.xcodeproj -scheme KeyMinder -configuration Debug \
>   -derivedDataPath /tmp/KeyMinder-build build 2>&1 | tail -20
> ```
> Bump the patch version in `project.pbxproj`.

---

### Phase 3 — Move tap to a background run loop (Bug 4)

**Effort:** Moderate threading change; needs careful review.  
**Model:** claude-opus-4-8 | **Effort level:** high

**Prompt:**

> You are improving the reliability of `KeyMinder/Settings/DoubleTapTrigger.swift`
> by moving the CGEventTap source off the main run loop onto a dedicated background
> run loop thread.
>
> **Current situation**: the run loop source is attached to `CFRunLoopGetMain()`.
> If the main thread is briefly busy (SwiftUI layout, popup animation) when
> `flagsChanged` events arrive, delivery is delayed and the 500 ms timing window
> becomes unreliable.
>
> **Required change**:
> 1. Add a `private var tapThread: Thread?` and `private var tapRunLoop: CFRunLoop?`
>    to `DoubleTapTrigger`.
> 2. In `installTap()`, instead of adding the source to `CFRunLoopGetMain()`, spin up
>    a new `Thread` whose `main` body adds the source to its own `CFRunLoop` and then
>    calls `CFRunLoopRun()`. Capture the run loop via `CFRunLoopGetCurrent()` before
>    calling `CFRunLoopRun()`, store it in `tapRunLoop`.
> 3. In `stop()`, after disabling the tap and removing the source, also invalidate
>    the run loop (`CFRunLoopStop(tapRunLoop)`) and nil out `tapThread` and `tapRunLoop`.
> 4. The C callback `doubleTapCCallback` calls `MainActor.assumeIsolated`. Since the
>    callback now fires on a background thread rather than the main thread, this call
>    will **crash or produce undefined behaviour** — `assumeIsolated` is only valid
>    on the main thread. Fix this by replacing the `assumeIsolated` call with a
>    proper main-actor dispatch: `DispatchQueue.main.async { trigger.handle(...) }`.
>    Because `handle(type:event:)` is now called asynchronously, the `event` parameter
>    (a `CGEvent`) must be retained; use `event.copy()` before the async block and
>    pass the copy, OR read the fields you need (flags, type raw value) synchronously
>    before dispatching only the extracted values. The latter is cleaner.
> 5. The `DoubleTapTrigger` class is `@MainActor`; all mutation of `prevFlags`,
>    `tapState`, etc., remains on the main actor — the background thread only receives
>    the raw CGEvent and dispatches extracted values to the main actor.
>
> **Constraint**: The class signature, public API (`start`, `stop`, `onActivate`), and
> `@MainActor` isolation must not change. Only the internal tap-plumbing changes.
>
> After the change:
> - Compile with the standard xcodebuild command (see CLAUDE.md).
> - Confirm that `MainActor.assumeIsolated` is **removed** from the C callback.
> - Confirm that `stop()` properly signals and tears down the background thread.
>
> Bump the patch version in `project.pbxproj`.

---

### Phase 4 — Surface tap health in Settings UI (optional UX improvement)

**Effort:** Small UI addition; independent of the bugs above.  
**Model:** claude-sonnet-4-6 | **Effort level:** medium

**Prompt:**

> Add a visible health indicator to the double-tap section of
> `KeyMinder/UI/Settings/SettingsView.swift` so users know if the event tap is
> active or disabled.
>
> 1. Add a `var tapIsActive: Bool` computed property to `DoubleTapTrigger` that
>    returns `true` if `eventTap != nil` and the tap is enabled
>    (`CGEvent.tapIsEnabled(tap:)`). Make it `@MainActor`.
> 2. In `SettingsModel`, add `var doubleTapHealthy: Bool` that forwards to
>    `DoubleTapTrigger.shared.tapIsActive`. Update it from a 2-second `Timer`
>    while the Settings window is open (start/stop the timer in a `.onAppear` /
>    `.onDisappear` modifier on the double-tap section).
> 3. In `SettingsView`, below the Enable toggle, when `model.doubleTapEnabled &&
>    !model.doubleTapHealthy`, show a small warning label:
>    `"Tap disabled — quit and relaunch KeyMinder"` in `.orange` at `.caption`
>    size.
>
> Keep the warning invisible when the tap is healthy or disabled by the user.
> Bump the patch version.

---

### Phase 5 — Conflicting app detection (optional, future)

If the above fixes don't fully resolve intermittent failures, a conflicting app
(Raycast, Alfred, 1Password, Bartender, etc.) may be consuming modifier events at
a higher event-tap priority level. Detection approach:

- Use `CGGetEventTapList()` at app launch to enumerate all active event taps in
  the session.
- If any tap with `.headInsertEventTap` placement and a non-listenOnly option is
  found at a higher position than ours, log the owning PID and process name.
- Optionally surface a warning in Settings: "Another app (Raycast) may intercept
  modifier keys before KeyMinder."

This is best done as a standalone investigation step before writing code; prompt
for it once the Phase 1–3 fixes are shipped and the problem persists.

---

## Execution order

```
Phase 1  →  Phase 2  →  Phase 3  →  verify  →  (Phase 4 if desired)
```

Each phase is one commit. After Phase 3, build and install to `/Applications` per
CLAUDE.md, stream logs, and manually verify the double-tap fires reliably across:
- Cold launch
- After granting Accessibility (first-run flow)
- After system wake from sleep
- With the popup already visible (toggle-off path)

## Log commands for verification

```bash
# Stream all hotkey-related events
/usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder' AND category == 'hotkey'"

# Grep session log for tap-disable events (after testing)
/usr/bin/log show --last 5m --predicate "subsystem == 'org.afaik.KeyMinder'" | grep -i "tap"
```

Healthy session after Phase 1–3:
- `DoubleTapTrigger: watching command` — tap installed at launch
- No `tapDisabledBy*` lines, or if they appear, immediately followed by `re-enabling`
- `DoubleTapTrigger: watching command` again after wake — tap re-armed
