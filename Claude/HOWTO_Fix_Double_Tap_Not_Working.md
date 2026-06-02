# HOWTO: Fix Double-Tap Trigger Not Working

## Current implementation (v0.1.48+)

The double-tap trigger uses `NSEvent.addGlobalMonitorForEvents` (not CGEventTap).
This means it is **not** subject to `tapDisabledByUserInput` or other CGEventTap
reliability issues. The only hard requirement is the **Accessibility TCC permission**,
which KeyMinder already needs for menu scraping.

---

## Symptoms & fixes

### Symptom: double-tap does nothing at all

**Most likely cause:** Accessibility permission is not granted or was reset.

**Fix:**

1. Open **System Settings → Privacy & Security → Accessibility**
2. Confirm KeyMinder is in the list and its toggle is **on**
3. If not listed, relaunch KeyMinder — it will show the onboarding screen; click
   **Grant Access** and enable the toggle

KeyMinder re-arms the trigger the moment permission is granted (no relaunch needed
as of v0.1.45).

**Verify** by streaming logs during a double-tap attempt:

```
/usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder' AND category == 'hotkey'"
```

A healthy trigger logs `DoubleTapTrigger: watching command` at startup and
`DoubleTapTrigger: FIRED` on each successful double-tap.

---

### Symptom: double-tap stopped working after the Mac woke from sleep

`NSEvent` global monitors can be invalidated when the session is locked/unlocked
or the Mac sleeps. KeyMinder automatically re-arms the trigger on
`NSWorkspace.didWakeNotification` (added in v0.1.45).

If you're on v0.1.45+, this should be self-healing. If it persists, quit and
relaunch KeyMinder.

---

### Symptom: trigger works sometimes but fires at the wrong time, or requires
more than two presses

Check that no other modifier key is held when double-tapping. The state machine
rejects any press where another modifier is simultaneously held (treats it as a
chord and resets to idle). Also verify the configured modifier in Settings matches
what you're pressing.

---

### Symptom: trigger never fires despite permission being granted (developer build)

This was the pre-v0.1.48 CGEventTap issue where macOS 15 would fire
`tapDisabledByUserInput` on virtually every keypress, silently killing the tap.
This is fully resolved in v0.1.48 by the switch to `NSEvent.addGlobalMonitorForEvents`.

If you are on a pre-v0.1.48 build, update to v0.1.48+.

---

## Diagnostic log commands

```bash
# Basic trigger health (info level)
/usr/bin/log stream --level info --predicate "subsystem == 'org.afaik.KeyMinder' AND category == 'hotkey'"

# Full state machine trace (debug level — very verbose, one line per keypress)
/usr/bin/log stream --level debug --predicate "subsystem == 'org.afaik.KeyMinder' AND category == 'hotkey'"
```

Healthy startup output:
```
DoubleTapTrigger: watching command
```

Successful double-tap output:
```
DoubleTapTrigger: flags 0x... isDown=true  wasDown=false state=idle      → firstDown
DoubleTapTrigger: flags 0x... isDown=false wasDown=true  state=firstDown → firstUp
DoubleTapTrigger: flags 0x... isDown=true  wasDown=false state=firstUp   → idle
DoubleTapTrigger: FIRED
```

---

## History

Prior to v0.1.48, the trigger used a `CGEventTap` (listen-only, session-level).
On macOS 15, `tapDisabledByUserInput` fired on virtually every keypress — even for
listen-only taps, contrary to documentation — causing the tap to go dark between
events and lose track of modifier state (`prevFlags` desync). Multiple synchronous
re-enable attempts failed because the CGEventTap port could become invalid before
the re-enable reached it. The root cause was confirmed via `--level debug` log
traces. Replaced entirely with `NSEvent.addGlobalMonitorForEvents` in v0.1.48.
