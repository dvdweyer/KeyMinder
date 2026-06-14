import AppKit

/// A KeyMinder-native action that can be offered as an alternative when the user
/// presses a shortcut that belongs to an ignored menu in the frontmost app.
struct KeyMinderAction {
    let title: String
    let handler: () -> Void
}

enum KeyMinderActions {
    /// Returns the KeyMinder-native action for a given key string, if one exists.
    /// `onOpenSettings` is passed in so the caller controls the Settings flow.
    static func action(for keys: String, onOpenSettings: (() -> Void)?) -> KeyMinderAction? {
        switch keys {
        case "⌘Q":
            return KeyMinderAction(title: String(localized: "Quit KeyMinder")) {
                NSApp.terminate(nil)
            }
        case "⌘,":
            guard let fn = onOpenSettings else { return nil }
            return KeyMinderAction(title: String(localized: "Open KeyMinder Settings")) { fn() }
        default:
            return nil
        }
    }
}
