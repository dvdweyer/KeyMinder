import AppKit
import SwiftUI

/// Manages user-facing appearance preferences, specifically the key-badge accent colour.
/// `@Observable` so popup and settings views react to changes without extra wiring.
@Observable @MainActor
final class ThemeSettings {
    static let shared = ThemeSettings()
    private init() {}

    /// `nil` = follow the system accent colour (`NSColor.controlAccentColor`).
    private(set) var customColor: NSColor? = UserDefaults.standard.keyAccentColor

    /// The resolved accent colour for use in SwiftUI views.
    var keyAccent: Color {
        Color(nsColor: customColor ?? .controlAccentColor)
    }

    var followsSystemAccent: Bool { customColor == nil }

    func setCustomColor(_ color: Color) {
        let ns = NSColor(color)
        customColor = ns
        UserDefaults.standard.keyAccentColor = ns
    }

    /// Switches to custom mode starting from the current displayed colour so the
    /// picker opens showing exactly what was already on screen.
    func enableCustom() {
        setCustomColor(Color(nsColor: customColor ?? .controlAccentColor))
    }

    func resetToSystem() {
        customColor = nil
        UserDefaults.standard.keyAccentColor = nil
    }
}

// MARK: - UserDefaults persistence

private extension UserDefaults {
    var keyAccentColor: NSColor? {
        get {
            guard let data = data(forKey: "keyAccentColor") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        }
        set {
            if let color = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: color,
                                                             requiringSecureCoding: true) {
                set(data, forKey: "keyAccentColor")
            } else {
                removeObject(forKey: "keyAccentColor")
            }
        }
    }
}
