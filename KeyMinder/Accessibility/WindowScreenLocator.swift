// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices

/// Locates the `NSScreen` containing a running application's frontmost window,
/// via the Accessibility API. Used to show the popup on the screen the user is
/// actually working on, rather than wherever the mouse cursor happens to be.
enum WindowScreenLocator {

    /// Returns the screen containing the focused (or main) window of the app
    /// with the given pid, or `nil` if no window frame could be read — e.g. the
    /// app has no windows, or the AX call failed for any other reason. Callers
    /// should fall back to another screen-selection strategy on `nil`.
    static func screen(forFrontmostPID pid: pid_t) -> NSScreen? {
        let appElement = AXUIElementCreateApplication(pid)

        guard let window = window(appElement, kAXFocusedWindowAttribute)
                        ?? window(appElement, kAXMainWindowAttribute),
              let position = point(window, kAXPositionAttribute),
              let size = size(window, kAXSizeAttribute),
              // AppKit guarantees screens[0] is the display containing the menu
              // bar, whose origin is (0,0) in Cocoa's global coordinate space —
              // used here to flip AX's top-left/y-down coordinates to Cocoa's
              // bottom-left/y-up ones.
              let primary = NSScreen.screens.first
        else { return nil }

        let cocoaY = primary.frame.height - position.y - size.height
        let center = CGPoint(x: position.x + size.width / 2, y: cocoaY + size.height / 2)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    // CF types have no runtime type metadata so as?/as! both error in Xcode 26;
    // unsafeBitCast is safe here because the CFGetTypeID checks below confirm the type.

    private static func window(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let axValue = axValue(element, attribute) else { return nil }
        var result = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &result) else { return nil }
        return result
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let axValue = axValue(element, attribute) else { return nil }
        var result = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &result) else { return nil }
        return result
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXValue.self)
    }
}
