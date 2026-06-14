import AppKit

// MARK: - AppIconVariant

enum AppIconVariant: Int, CaseIterable {
    case command = 0
    case option  = 1
    case control = 2

    var label: String {
        switch self {
        case .command: return "⌘ Command"
        case .option:  return "⌥ Option"
        case .control: return "⌃ Control"
        }
    }

    /// Named image from the asset catalog, or nil to use the default bundle icon.
    var imageName: String? {
        switch self {
        case .command: return nil
        case .option:  return "AppIconOption"
        case .control: return "AppIconControl"
        }
    }

    /// Applies this variant as the running application's icon.
    @MainActor
    func apply() {
        if let name = imageName, let img = NSImage(named: name) {
            img.size = NSSize(width: 1024, height: 1024)
            NSApp.applicationIconImage = img
        } else {
            NSApp.applicationIconImage = nil   // revert to bundle icon
        }
    }
}

// MARK: - UserDefaults

extension UserDefaults {
    private static let appIconVariantKey = "appIconVariant"

    var appIconVariant: AppIconVariant {
        get { AppIconVariant(rawValue: integer(forKey: Self.appIconVariantKey)) ?? .command }
        set { set(newValue.rawValue, forKey: Self.appIconVariantKey) }
    }
}
