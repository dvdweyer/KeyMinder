import ApplicationServices
import AppKit

/// Reads the menu bar of a running application via the Accessibility API and
/// extracts its keyboard shortcuts, grouped by top-level menu.
///
/// Requires Accessibility permission. Without it, every attribute read fails and
/// this returns an empty array.
enum MenuScraper {

    /// Scrapes the menu bar of the application with the given process id.
    static func scrape(pid: pid_t) -> [MenuSection] {
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return [] }

        var sections: [MenuSection] = []
        for menuBarItem in children(menuBar) {
            let title = string(menuBarItem, kAXTitleAttribute) ?? ""
            // A menu bar item owns its drop-down menu as its single child.
            guard let menu = children(menuBarItem).first else { continue }
            let shortcuts = collectShortcuts(in: menu)
            if !shortcuts.isEmpty {
                sections.append(MenuSection(title: title, shortcuts: shortcuts))
            }
        }
        return sections
    }

    /// Walks a menu (and any submenus) collecting items that have a key equivalent.
    private static func collectShortcuts(in menu: AXUIElement) -> [Shortcut] {
        var result: [Shortcut] = []
        for item in children(menu) {
            if let title = string(item, kAXTitleAttribute), !title.isEmpty {
                let keys = ShortcutFormatter.format(
                    cmdChar: string(item, kAXMenuItemCmdCharAttribute),
                    virtualKey: int(item, kAXMenuItemCmdVirtualKeyAttribute),
                    glyph: int(item, kAXMenuItemCmdGlyphAttribute),
                    modifiers: int(item, kAXMenuItemCmdModifiersAttribute) ?? 0
                )
                if let keys {
                    result.append(Shortcut(title: title, keys: keys))
                }
            }
            // Recurse into a submenu if this item has one.
            if let submenu = children(item).first {
                result.append(contentsOf: collectShortcuts(in: submenu))
            }
        }
        return result
    }

    // MARK: - Accessibility helpers

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        (value(element, attribute) as? NSNumber)?.intValue
    }
}
