import CoreGraphics
import AppKit
import os

// MARK: - DoubleTapModifier

/// A modifier key that can trigger double-tap activation.
enum DoubleTapModifier: String, CaseIterable, Codable {
    case command
    case option
    case control

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option:  "⌥"
        case .control: "⌃"
        }
    }

    var label: String {
        switch self {
        case .command: "Command"
        case .option:  "Option"
        case .control: "Control"
        }
    }

    /// The `CGEventFlags` bit for this modifier.
    var cgFlag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option:  .maskAlternate
        case .control: .maskControl
        }
    }
}

// MARK: - DoubleTapTrigger

/// Fires `onActivate` when the user quickly presses and releases the same modifier key twice,
/// without any other key held at the same time.
///
/// Uses a passive, listen-only `CGEventTap` attached to the main run loop.
/// Requires the Accessibility permission that KeyMinder already holds for menu scraping.
@MainActor
final class DoubleTapTrigger {

    static let shared = DoubleTapTrigger()

    /// Called on the main thread when a qualifying double-tap is detected.
    var onActivate: (() -> Void)?

    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State machine — all mutations happen on the main thread:
    // the run loop source is attached to CFRunLoopGetMain().
    private var prevFlags: CGEventFlags = []
    private var tapState:  TapState    = .idle
    private var watched:   DoubleTapModifier = .command

    private enum TapState {
        case idle
        case firstDown
        case firstUp(at: Date)
    }

    /// Maximum interval (seconds) between first release and second press to count as a double-tap.
    private static let window: TimeInterval = 0.35

    private init() {}

    // MARK: - Public API

    /// Start (or restart) monitoring for double-taps of `modifier`.
    func start(modifier: DoubleTapModifier) {
        stop()
        watched   = modifier
        prevFlags = []
        tapState  = .idle
        installTap()
    }

    /// Stop monitoring.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        tapState = .idle
    }

    // MARK: - Tap installation

    private func installTap() {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        // passUnretained is safe: DoubleTapTrigger.shared is a singleton whose
        // lifetime exceeds the tap's, and stop() is called before any dealloc.
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap:              .cgSessionEventTap,
            place:            .headInsertEventTap,
            options:          .listenOnly,
            eventsOfInterest: mask,
            callback:         doubleTapCCallback,
            userInfo:         ctx
        ) else {
            Logger.hotkey.error("DoubleTapTrigger: CGEventTapCreate failed — check Accessibility permission")
            return
        }

        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap      = tap
        runLoopSource = src
        Logger.hotkey.info("DoubleTapTrigger: watching \(self.watched.rawValue, privacy: .public)")
    }

    // MARK: - Event handling — called from the C callback on the main run loop

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // macOS may disable the tap if it's slow; re-enable immediately.
        if type == .tapDisabledByTimeout {
            Logger.hotkey.warning("DoubleTapTrigger: re-enabling tap after timeout")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        switch type {
        case .keyDown:      tapState = .idle   // any regular keypress resets the sequence
        case .flagsChanged: handleFlags(event)
        default:            break
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let flags    = event.flags
        // Mask down to the four modifier bits we care about, ignoring
        // device-dependent bits, Fn, Caps Lock, etc.
        let modMask  = CGEventFlags(rawValue:
            CGEventFlags.maskCommand.rawValue  |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskControl.rawValue  |
            CGEventFlags.maskShift.rawValue
        )
        let curr = CGEventFlags(rawValue: flags.rawValue     & modMask.rawValue)
        let prev = CGEventFlags(rawValue: prevFlags.rawValue & modMask.rawValue)
        defer { prevFlags = flags }

        let bit     = watched.cgFlag
        let wasDown = (prev.rawValue & bit.rawValue) != 0
        let isDown  = (curr.rawValue & bit.rawValue) != 0

        if isDown, !wasDown {
            // ── Leading edge: modifier pressed ──
            // Abort if any other modifier is also held (this is a chord, not a solo tap).
            guard curr.rawValue == bit.rawValue else { tapState = .idle; return }

            switch tapState {
            case .idle:
                tapState = .firstDown

            case .firstDown:
                break   // unexpected double-down without a release; stay put

            case .firstUp(let t):
                if Date().timeIntervalSince(t) < Self.window {
                    tapState = .idle
                    onActivate?()           // already on the main thread
                } else {
                    // Window expired; treat this press as the new first press.
                    tapState = .firstDown
                }
            }

        } else if !isDown, wasDown {
            // ── Trailing edge: modifier released ──
            switch tapState {
            case .firstDown:
                // Only advance if no other modifier is still held.
                tapState = curr.rawValue == 0 ? .firstUp(at: Date()) : .idle
            default:
                tapState = .idle
            }
        }
    }
}

// MARK: - C event callback (fires on the main run loop)

/// Top-level C-compatible callback. The run loop source is attached to
/// `CFRunLoopGetMain()`, so this always executes on the main thread.
private let doubleTapCCallback: CGEventTapCallBack = { _, type, event, ctx in
    guard let ctx else { return nil }
    let trigger = Unmanaged<DoubleTapTrigger>.fromOpaque(ctx).takeUnretainedValue()
    // We are on the main thread; assumeIsolated lets us enter the @MainActor
    // domain without a suspension point.
    MainActor.assumeIsolated { trigger.handle(type: type, event: event) }
    return nil  // listen-only tap: return value is ignored by the system
}

// MARK: - UserDefaults

extension UserDefaults {
    private static let dtEnabledKey  = "doubleTapEnabled"
    private static let dtModifierKey = "doubleTapModifier"

    var doubleTapEnabled: Bool {
        get { bool(forKey: Self.dtEnabledKey) }
        set { set(newValue, forKey: Self.dtEnabledKey) }
    }

    var doubleTapModifier: DoubleTapModifier {
        get {
            guard let raw = string(forKey: Self.dtModifierKey),
                  let mod = DoubleTapModifier(rawValue: raw) else { return .command }
            return mod
        }
        set { set(newValue.rawValue, forKey: Self.dtModifierKey) }
    }
}
