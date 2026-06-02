# Security Policy

## Supported Versions

Only the latest release of KeyMinder receives security fixes.  
Older versions are unsupported; please upgrade before filing a report.

| Version | Supported |
|---------|-----------|
| Latest  | ✓         |
| Older   | ✗         |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately by emailing **keyminder@afaik.org** (or use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
if enabled on this repository).

Please include:

- A description of the vulnerability and its potential impact
- macOS version and KeyMinder version
- Step-by-step reproduction instructions
- Proof-of-concept code or screenshots, if available

We aim to acknowledge reports within **3 business days** and to provide an
initial assessment within **7 business days**.

## Disclosure Policy

We follow **coordinated disclosure**:

1. Reporter notifies us privately.
2. We investigate and, if confirmed, develop a fix.
3. A patched release ships within **90 days** of confirmation, usually sooner.
4. Reporter and we agree on a disclosure date (typically when the fix is
   published).
5. A GitHub Security Advisory is published at release time.

If we cannot meet the 90-day window we will explain why and propose a revised
timeline.

## Scope

### In scope

- **Privilege escalation or sandbox escape** — anything that lets a malicious
  app or local user gain elevated privileges via KeyMinder.
- **Accessibility API misuse** — KeyMinder requests the Accessibility permission
  to read the frontmost app's menu bar. Any path by which a third party could
  leverage that grant to exfiltrate data or control the user's machine is in
  scope.
- **Global hotkey / event monitor hijacking** — KeyMinder installs a system-wide
  keyboard listener (Carbon `RegisterEventHotKey` + `NSEvent.addGlobalMonitorForEvents`).
  Vulnerabilities that let an attacker intercept keystrokes beyond the registered
  hotkey or double-tap modifier are in scope.
- **Code-execution via malformed input** — crashes or code execution triggered
  by specially crafted app names, menu titles, or shortcut strings scraped from
  a target application.
- **Supply-chain issues** — compromised release artifacts or build toolchain
  tampering.

### Out of scope

- Theoretical attacks that require the attacker to already have local admin
  access or the ability to run arbitrary code on the machine.
- UI redressing / "clickjacking" of the popup panel.
- Reports against macOS itself or third-party applications whose menu data
  KeyMinder reads.
- Missing security headers, certificate pinning, or other web/network hardening
  (KeyMinder has no network stack).
- Denial-of-service via the Accessibility API that requires the attacker to
  already control the target application.

## Threat Model

KeyMinder is a local, non-sandboxed macOS utility with no network connectivity
and no remote backend. Its attack surface is:

1. **The Accessibility API grant** — KeyMinder reads menu-bar structure from
   the frontmost app. It does not inject input, does not read window contents,
   and does not access files outside its own container.
2. **Global NSEvent monitors** (`NSEvent.addGlobalMonitorForEvents`) registered for
   double-tap trigger detection (`.flagsChanged` + `.keyDown`) and for modifier key
   filter state while the popup is visible (`.flagsChanged` only — reads which modifier
   keys are held, not what the user types). All monitors are passive-only; they cannot
   suppress or synthesize events. No CGEventTap is used.
3. **Parsing of AX attribute values** (strings) returned by target applications.
   A malicious app could return unexpected data here.

## Security Best Practices for Users

- Download KeyMinder only from the [official releases page](../../releases) or
  the project website. All release builds are notarized by Apple.
- Verify the Developer ID signature before running:
  ```
  codesign -dv --verbose=4 /Applications/KeyMinder.app
  spctl --assess --type execute /Applications/KeyMinder.app
  ```
- Grant the Accessibility permission only to the copy installed in
  `/Applications`. KeyMinder does not need Full Disk Access, Screen Recording,
  or any other TCC permission.
- If you no longer use KeyMinder, revoke its Accessibility permission:
  ```
  tccutil reset Accessibility org.afaik.KeyMinder
  ```
