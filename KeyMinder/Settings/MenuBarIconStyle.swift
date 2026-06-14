import AppKit

// MARK: - MenuBarIconStyle

enum MenuBarIconStyle: Int, CaseIterable {
    case keyboard = 0
    case command  = 1
    case option   = 2
    case control  = 3

    var label: String {
        switch self {
        case .keyboard: return "⌨ Keyboard"
        case .command:  return "⌘ Command"
        case .option:   return "⌥ Option"
        case .control:  return "⌃ Control"
        }
    }

    func makeImage() -> NSImage {
        switch self {
        case .keyboard:
            let img = NSImage(systemSymbolName: "keyboard",
                              accessibilityDescription: "KeyMinder") ?? characterImage("⌨")
            img.isTemplate = true
            return img
        case .command: return characterImage("⌘")
        case .option:  return characterImage("⌥")
        case .control: return characterImage("⌃")
        }
    }

    private func characterImage(_ char: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let str = char as NSString
            let strSize = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(
                x: (rect.width  - strSize.width)  / 2,
                y: (rect.height - strSize.height) / 2
            ), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - UserDefaults

extension UserDefaults {
    private static let menuBarIconStyleKey = "menuBarIconStyle"

    var menuBarIconStyle: MenuBarIconStyle {
        get { MenuBarIconStyle(rawValue: integer(forKey: Self.menuBarIconStyleKey)) ?? .keyboard }
        set { set(newValue.rawValue, forKey: Self.menuBarIconStyleKey) }
    }
}
