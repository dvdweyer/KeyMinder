import Carbon.HIToolbox
import os

/// Registers and fires a single application-wide hotkey via Carbon's
/// `RegisterEventHotKey`.  Lifetime: a singleton held for the entire app run.
///
/// Usage:
/// ```swift
/// HotkeyManager.shared.onActivate = { togglePopup() }
/// HotkeyManager.shared.register(savedHotkey)
/// ```
final class HotkeyManager {

    static let shared = HotkeyManager()

    /// Called on the main thread whenever the registered hotkey is pressed.
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // "KMdr" — unique four-char code to distinguish our event from others.
    private static let signature: OSType = 0x4B4D_6472
    private static let eventID:   UInt32 = 1

    private init() {
        installCarbonHandler()
    }

    // MARK: - Public API

    func register(_ hotkey: GlobalHotkey) {
        unregister()
        // EventHotKeyID is passed by value to RegisterEventHotKey.
        let hkID = EventHotKeyID(signature: HotkeyManager.signature,
                                  id: HotkeyManager.eventID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            Logger.hotkey.info("registered hotkey: \(hotkey.displayString, privacy: .public)")
        } else {
            Logger.hotkey.error("RegisterEventHotKey failed, status=\(status)")
        }
    }

    func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
        Logger.hotkey.info("unregistered hotkey")
    }

    // MARK: - Carbon event handler

    private func installCarbonHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        // Pass a raw (unretained) pointer to self as the userData context.
        // Safe because the singleton lives for the app lifetime.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // InstallApplicationEventHandler is a C macro; call its expansion directly.
        InstallEventHandler(
            GetApplicationEventTarget(),
            // Non-capturing C closure — all context flows through userData.
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let mgr = Unmanaged<HotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if hkID.id == HotkeyManager.eventID {
                    DispatchQueue.main.async { mgr.onActivate?() }
                }
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )
    }
}
