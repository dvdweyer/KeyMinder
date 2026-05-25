import ApplicationServices
import AppKit
import os

/// Reads the menu bar of a running application via the Accessibility API and
/// extracts its keyboard shortcuts, grouped by top-level menu.
///
/// Requires Accessibility permission. Without it, every attribute read fails and
/// this returns an empty array.
enum MenuScraper {

    /// Scrapes the menu bar of the application with the given process id.
    static func scrape(pid: pid_t) -> [MenuSection] {
        let start = Date()
        let app = AXUIElementCreateApplication(pid)
        // Cap per-request AX round-trips so an unresponsive target never blocks
        // KeyMinder's main thread for more than ~1 second.
        AXUIElementSetMessagingTimeout(app, 1.0)

        guard let menuBar = element(app, kAXMenuBarAttribute) else {
            Logger.scraper.error("Could not read menu bar (pid \(pid, privacy: .public))")
            return []
        }

        var sections: [MenuSection] = []
        for menuBarItem in children(menuBar) {
            let title = string(menuBarItem, kAXTitleAttribute) ?? ""
            // A menu bar item owns its drop-down menu as its single child.
            guard let menu = children(menuBarItem).first else { continue }
            let groups = collectGroups(in: menu)
            if !groups.isEmpty {
                sections.append(MenuSection(title: title, groups: groups))
            }
        }

        let totalShortcuts = sections.reduce(0) { $0 + $1.shortcuts.count }
        let elapsed = Date().timeIntervalSince(start)
        Logger.scraper.info("pid \(pid, privacy: .public): \(sections.count, privacy: .public) menus, \(totalShortcuts, privacy: .public) shortcuts in \(elapsed, format: .fixed(precision: 3), privacy: .public)s")

        return sections
    }

    /// Walks the direct children of `menu` and returns shortcut groups:
    /// one unnamed group for top-level items with key equivalents, then one
    /// named group per submenu that contains at least one shortcut.
    /// Sub-submenus (depth > 2) are flattened into their parent's named group.
    private static func collectGroups(in menu: AXUIElement) -> [ShortcutGroup] {
        var topLevel: [Shortcut] = []
        var named:    [ShortcutGroup] = []

        for item in children(menu) {
            guard let title = string(item, kAXTitleAttribute), !title.isEmpty else { continue }

            // Collect this item's own shortcut, if any.
            if let keys = ShortcutFormatter.format(
                cmdChar:    string(item, kAXMenuItemCmdCharAttribute),
                virtualKey: int(item,    kAXMenuItemCmdVirtualKeyAttribute),
                glyph:      int(item,    kAXMenuItemCmdGlyphAttribute),
                modifiers:  int(item,    kAXMenuItemCmdModifiersAttribute) ?? 0
            ) {
                topLevel.append(Shortcut(title: title, keys: keys))
            }

            // If this item opens a submenu, collect its shortcuts as a named group.
            // collectShortcutsFlat recurses further but keeps everything in one list,
            // which is the right behaviour for sub-submenus (depth > 2).
            if let submenu = children(item).first {
                let submenuShortcuts = collectShortcutsFlat(in: submenu)
                if !submenuShortcuts.isEmpty {
                    named.append(ShortcutGroup(title: title, shortcuts: submenuShortcuts))
                } else {
                    // Log empty submenus so we can quantify how often lazy population
                    // hides shortcuts.  itemCount == 0 strongly suggests the submenu
                    // is populated lazily (NSMenu's menuNeedsUpdate: fires only when
                    // the menu is actually displayed, not when AX reads it).
                    let itemCount = children(submenu).count
                    let hint = itemCount == 0 ? "; likely lazy-populated" : ""
                    Logger.scraper.info("Submenu '\(title, privacy: .public)' yielded 0 shortcuts (\(itemCount, privacy: .public) child items\(hint, privacy: .public))")
                }
            }
        }

        var groups: [ShortcutGroup] = []
        if !topLevel.isEmpty {
            groups.append(ShortcutGroup(title: nil, shortcuts: topLevel))
        }
        groups.append(contentsOf: named)
        return groups
    }

    /// Recursively collects all shortcuts within `menu`, flattening any nested
    /// submenus into a single list. Used for submenu contents (depth ≥ 2).
    private static func collectShortcutsFlat(in menu: AXUIElement) -> [Shortcut] {
        var result: [Shortcut] = []
        for item in children(menu) {
            guard let title = string(item, kAXTitleAttribute), !title.isEmpty else { continue }
            if let keys = ShortcutFormatter.format(
                cmdChar:    string(item, kAXMenuItemCmdCharAttribute),
                virtualKey: int(item,    kAXMenuItemCmdVirtualKeyAttribute),
                glyph:      int(item,    kAXMenuItemCmdGlyphAttribute),
                modifiers:  int(item,    kAXMenuItemCmdModifiersAttribute) ?? 0
            ) {
                result.append(Shortcut(title: title, keys: keys))
            }
            // Flatten sub-submenus.
            if let submenu = children(item).first {
                let sub = collectShortcutsFlat(in: submenu)
                if sub.isEmpty {
                    let itemCount = children(submenu).count
                    let hint = itemCount == 0 ? "; likely lazy-populated" : ""
                    Logger.scraper.info("Nested submenu '\(title, privacy: .public)' yielded 0 shortcuts (\(itemCount, privacy: .public) child items\(hint, privacy: .public))")
                }
                result.append(contentsOf: sub)
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
