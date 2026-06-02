@preconcurrency import CoreFoundation
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
/// Uses a passive, listen-only `CGEventTap` running on a dedicated background thread so that
/// main-thread load (SwiftUI layout passes, popup animations) cannot delay event delivery and
/// distort the timing window. Callbacks are dispatched to the main actor before touching any
/// state.
///
/// Requires the Accessibility permission that KeyMinder already holds for menu scraping.
@MainActor
final class DoubleTapTrigger {

    static let shared = DoubleTapTrigger()

    /// Called on the main thread when a qualifying double-tap is detected.
    var onActivate: (() -> Void)?

    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread:     Thread?
    private var tapRunLoop:    CFRunLoop?

    // State machine — all mutations happen on the main actor via DispatchQueue.main.async.
    private var prevFlags: CGEventFlags = []
    private var tapState:  TapState    = .idle
    private var watched:   DoubleTapModifier = .command

    private enum TapState {
        case idle
        case firstDown
        case firstUp(at: Date)
    }

    /// Maximum interval (seconds) between first release and second press to count as a double-tap.
    private static let window: TimeInterval = 0.50

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
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
            tapRunLoop = nil
        }
        if let src = runLoopSource {
            CFRunLoopSourceInvalidate(src)
            runLoopSource = nil
        }
        tapThread = nil
        tapState  = .idle
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

        guard let src = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            Logger.hotkey.error("DoubleTapTrigger: CFMachPortCreateRunLoopSource failed")
            return
        }
        eventTap      = tap
        runLoopSource = src

        // Spin a dedicated thread so callbacks are delivered independently of main-thread load.
        // A semaphore lets the main thread capture the background run loop before returning;
        // the wait is sub-millisecond (the thread just calls CFRunLoopGetCurrent and signals).
        final class RunLoopBox: @unchecked Sendable { var value: CFRunLoop? }
        let box    = RunLoopBox()
        let sem    = DispatchSemaphore(value: 0)
        let srcRef = src    // non-optional local avoids the Sendable capture warning
        let t = Thread {
            box.value = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), srcRef, .commonModes)
            sem.signal()        // main thread may proceed; run loop is live
            CFRunLoopRun()      // blocks until stop() calls CFRunLoopStop
        }
        t.name = "org.afaik.KeyMinder.doubleTap"
        t.qualityOfService = .userInteractive
        tapThread = t
        t.start()
        sem.wait()
        tapRunLoop = box.value

        CGEvent.tapEnable(tap: tap, enable: true)
        Logger.hotkey.info("DoubleTapTrigger: watching \(self.watched.rawValue, privacy: .public)")
    }

    // MARK: - Event handling — dispatched to main actor from the background tap thread

    fileprivate func handle(type: CGEventType, flags: CGEventFlags) {
        // Discard queued callbacks that arrived after stop() was called.
        guard eventTap != nil else { return }

        // A listen-only tap is documented as never being disabled automatically, but
        // handle both disable types defensively so the tap survives on any OS version.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user-input"
            Logger.hotkey.warning("DoubleTapTrigger: re-enabling tap after \(reason, privacy: .public) disable")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        switch type {
        case .keyDown:      tapState = .idle   // any regular keypress resets the sequence
        case .flagsChanged: handleFlags(flags)
        default:            break
        }
    }

    private func handleFlags(_ flags: CGEventFlags) {
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
                    onActivate?()           // already on the main actor
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

// MARK: - C event callback (fires on the dedicated tap thread)

/// Top-level C-compatible callback. Runs on the background tap thread; dispatches
/// to the main actor for all state mutations. The CGEvent is only valid for the
/// duration of this callback, so required values are extracted synchronously before
/// the async dispatch.
private let doubleTapCCallback: CGEventTapCallBack = { _, type, event, ctx in
    guard let ctx else { return nil }
    let trigger = Unmanaged<DoubleTapTrigger>.fromOpaque(ctx).takeUnretainedValue()
    let capturedType  = type
    let capturedFlags = event.flags
    DispatchQueue.main.async {
        MainActor.assumeIsolated { trigger.handle(type: capturedType, flags: capturedFlags) }
    }
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
