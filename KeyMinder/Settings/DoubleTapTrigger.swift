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

    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option:  .option
        case .control: .control
        }
    }
}

// MARK: - DoubleTapTrigger

/// Fires `onActivate` when the user quickly presses and releases the same modifier key twice,
/// without any other key held at the same time.
///
/// Uses `NSEvent.addGlobalMonitorForEvents` — the standard AppKit API for system-wide
/// event monitoring. Runs on the main thread. Does not require CGEventTap and is not
/// affected by `tapDisabledByUserInput` events.
///
/// Requires the Accessibility permission that KeyMinder already holds for menu scraping.
@MainActor
final class DoubleTapTrigger {

    static let shared = DoubleTapTrigger()

    /// Called on the main thread when a qualifying double-tap is detected.
    var onActivate: (() -> Void)?

    private var flagsMonitor:   Any?
    private var keyDownMonitor: Any?

    private var prevFlags: NSEvent.ModifierFlags = []
    private var tapState:  TapState = .idle
    private var watched:   DoubleTapModifier = .command

    private enum TapState {
        case idle
        case firstDown
        case firstUp(at: Date)
    }

    private var tapStateName: String {
        switch tapState {
        case .idle:      return "idle"
        case .firstDown: return "firstDown"
        case .firstUp:   return "firstUp"
        }
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
        installMonitors()
    }

    /// Stop monitoring.
    func stop() {
        if let m = flagsMonitor   { NSEvent.removeMonitor(m); flagsMonitor   = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        tapState = .idle
    }

    // MARK: - Monitor installation

    private func installMonitors() {
        // NSEvent global monitors run on the main thread and are never disabled by the system.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event.modifierFlags) }
        }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            MainActor.assumeIsolated {
                if UserDefaults.standard.debugLoggingEnabled {
                    Logger.hotkey.debug("DoubleTapTrigger: keyDown reset (was \(self?.tapStateName ?? "?", privacy: .public))")
                }
                self?.tapState = .idle
            }
        }
        Logger.hotkey.info("DoubleTapTrigger: watching \(self.watched.rawValue, privacy: .public)")
    }

    // MARK: - Event handling

    func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let modMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let curr = flags.intersection(modMask)
        let prev = prevFlags.intersection(modMask)
        defer { prevFlags = flags }

        let bit     = watched.nsFlag
        let wasDown = prev.contains(bit)
        let isDown  = curr.contains(bit)

        if UserDefaults.standard.debugLoggingEnabled {
            Logger.hotkey.debug("DoubleTapTrigger: flags 0x\(String(flags.rawValue, radix: 16), privacy: .public) isDown=\(isDown, privacy: .public) wasDown=\(wasDown, privacy: .public) state=\(self.tapStateName, privacy: .public)")
        }

        if isDown, !wasDown {
            // ── Leading edge: modifier pressed ──
            // Abort if any other modifier is also held (this is a chord, not a solo tap).
            guard curr == [bit] else {
                if UserDefaults.standard.debugLoggingEnabled {
                    Logger.hotkey.debug("DoubleTapTrigger: chord — reset")
                }
                tapState = .idle; return
            }

            switch tapState {
            case .idle:
                tapState = .firstDown

            case .firstDown:
                break   // unexpected double-down without a release; stay put

            case .firstUp(let t):
                if Date().timeIntervalSince(t) < Self.window {
                    tapState = .idle
                    Logger.hotkey.info("DoubleTapTrigger: FIRED")
                    onActivate?()
                } else {
                    tapState = .firstDown
                }
            }
            if UserDefaults.standard.debugLoggingEnabled {
                Logger.hotkey.debug("DoubleTapTrigger: → \(self.tapStateName, privacy: .public)")
            }

        } else if !isDown, wasDown {
            // ── Trailing edge: modifier released ──
            switch tapState {
            case .firstDown:
                // Only advance if no other modifier is still held.
                tapState = curr.isEmpty ? .firstUp(at: Date()) : .idle
            default:
                tapState = .idle
            }
            if UserDefaults.standard.debugLoggingEnabled {
                Logger.hotkey.debug("DoubleTapTrigger: → \(self.tapStateName, privacy: .public)")
            }
        }
    }
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
