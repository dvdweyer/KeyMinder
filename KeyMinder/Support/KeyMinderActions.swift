import AppKit

/// A KeyMinder-native action that can be offered as an alternative when the user
/// presses a shortcut that belongs to an ignored menu in the frontmost app.
struct KeyMinderAction {
    let title: String
    var note: String? = nil
    let handler: () -> Void
}

enum KeyMinderActions {
    /// Returns the KeyMinder-native action for a given key string, if one exists.
    /// Pass closures only for the actions you want to support; a nil closure
    /// suppresses the corresponding case (so the option isn't shown).
    static func action(for keys: String,
                       onOpenSettings: (() -> Void)?,
                       onClose: (() -> Void)? = nil) -> KeyMinderAction? {
        switch keys {
        case "⌘Q", "⌥⌘Q":
            return KeyMinderAction(title: String(localized: "Quit KeyMinder")) {
                NSApp.terminate(nil)
            }
        case "⌘,":
            guard let fn = onOpenSettings else { return nil }
            return KeyMinderAction(title: String(localized: "Open KeyMinder Settings")) { fn() }
        case "⌘W":
            guard let fn = onClose else { return nil }
            return KeyMinderAction(
                title: String(localized: "Close KeyMinder Popup"),
                note: String(localized: "Tip: press Esc to dismiss the popup")
            ) { fn() }
        default:
            return nil
        }
    }
}
