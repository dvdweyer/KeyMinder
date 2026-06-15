// SPDX-License-Identifier: GPL-3.0-or-later
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
    /// When `includeItemsWithoutShortcuts` is true, leaf menu items that have no
    /// key equivalent are included with an empty `keys` string so the full menu
    /// structure is visible in the popup.
    static func scrape(pid: pid_t, includeItemsWithoutShortcuts: Bool = false,
                       ignoredTitles: [String] = [],
                       ignoredMenuTitles: [String] = [],
                       maxShortcutFreeSubmenuSize: Int? = nil) -> [MenuSection] {
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
            guard !IgnoreListStore.isIgnored(title: title, patterns: ignoredMenuTitles) else { continue }
            // A menu bar item owns its drop-down menu as its single child.
            guard let menu = children(menuBarItem).first else { continue }
            let groups = collectGroups(in: menu, includeAll: includeItemsWithoutShortcuts, ignoredTitles: ignoredTitles, maxShortcutFreeSubmenuSize: maxShortcutFreeSubmenuSize)
            if !groups.isEmpty {
                sections.append(MenuSection(title: title, groups: groups))
            }
        }

        let totalItems = sections.reduce(0) { $0 + $1.shortcuts.count }
        let elapsed = Date().timeIntervalSince(start)
        Logger.scraper.info("pid \(pid, privacy: .public): \(sections.count, privacy: .public) menus, \(totalItems, privacy: .public) items in \(elapsed, format: .fixed(precision: 3), privacy: .public)s")

        return sections
    }

    /// Scrapes only the menus whose titles match `ignoredMenuTitles` and returns
    /// their shortcuts as a flat list. Used to enable chord disambiguation for
    /// shortcuts that are intentionally hidden from the popup display.
    static func scrapeIgnoredMenus(pid: pid_t, ignoredMenuTitles: [String]) -> [Shortcut] {
        guard !ignoredMenuTitles.isEmpty else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return [] }
        var result: [Shortcut] = []
        for menuBarItem in children(menuBar) {
            let title = string(menuBarItem, kAXTitleAttribute) ?? ""
            guard IgnoreListStore.isIgnored(title: title, patterns: ignoredMenuTitles) else { continue }
            guard let menu = children(menuBarItem).first else { continue }
            result.append(contentsOf: collectShortcutsFlat(in: menu).shortcuts)
        }
        return result
    }

    /// Walks the direct children of `menu` and returns shortcut groups:
    /// one unnamed group for top-level items, then one named group per submenu
    /// that has at least one item. Sub-submenus (depth > 2) are flattened into
    /// their parent's named group.
    /// When `includeAll` is false (default), only items with a key equivalent are
    /// included. When true, leaf items without shortcuts are also included.
    private static func collectGroups(in menu: AXUIElement, includeAll: Bool,
                                      ignoredTitles: [String],
                                      maxShortcutFreeSubmenuSize: Int? = nil) -> [ShortcutGroup] {
        var topLevel: [Shortcut] = []
        var named:    [ShortcutGroup] = []

        for item in children(menu) {
            let title = string(item, kAXTitleAttribute) ?? ""
            if title.isEmpty {
                topLevel.append(.separator())
                continue
            }
            guard !IgnoreListStore.isIgnored(title: title, patterns: ignoredTitles) else { continue }

            let rawChar     = string(item, kAXMenuItemCmdCharAttribute)
            let rawVKey     = int(item,    kAXMenuItemCmdVirtualKeyAttribute)
            let rawGlyph    = int(item,    kAXMenuItemCmdGlyphAttribute)
            let rawMods     = int(item,    kAXMenuItemCmdModifiersAttribute)
            let shortcutKeys = ShortcutFormatter.format(
                cmdChar:    rawChar,
                virtualKey: rawVKey,
                glyph:      rawGlyph,
                modifiers:  rawMods ?? 0
            )
            // Read children once: nil means a leaf item, non-nil means a submenu container.
            let submenu = children(item).first

            if let keys = shortcutKeys {
                topLevel.append(Shortcut(title: title, keys: keys, axElement: item, isDisabled: false))
            } else if includeAll, submenu == nil {
                // Leaf item with no shortcut: include with empty keys so the full
                // menu structure is discoverable.
                topLevel.append(Shortcut(title: title, keys: "", axElement: item, isDisabled: false))
            }

            if shortcutKeys == nil, submenu == nil, UserDefaults.standard.debugLoggingEnabled {
                let c = rawChar.map { "'\($0)'" } ?? "nil"
                let v = rawVKey.map(String.init) ?? "nil"
                let g = rawGlyph.map(String.init) ?? "nil"
                let m = rawMods.map(String.init) ?? "nil"
                Logger.scraper.debug("No shortcut for '\(title, privacy: .private)': char=\(c, privacy: .private) vkey=\(v, privacy: .private) glyph=\(g, privacy: .private) mods=\(m, privacy: .private)")
            }

            // If this item opens a submenu, collect its contents as a named group.
            // collectShortcutsFlat recurses further but keeps everything in one list,
            // which is the right behaviour for sub-submenus (depth > 2).
            if let submenu {
                let (submenuItems, rawChildCount) = collectShortcutsFlat(in: submenu, includeAll: includeAll, ignoredTitles: ignoredTitles)
                if submenuItems.isEmpty {
                    // Log empty submenus so we can quantify how often lazy population
                    // hides shortcuts.  rawChildCount == 0 strongly suggests the submenu
                    // is populated lazily (NSMenu's menuNeedsUpdate: fires only when
                    // the menu is actually displayed, not when AX reads it).
                    let hint = rawChildCount == 0 ? "; likely lazy-populated" : ""
                    Logger.scraper.info("Submenu '\(title, privacy: .private)' yielded 0 items (\(rawChildCount, privacy: .public) child items\(hint, privacy: .private))")
                } else if let limit = maxShortcutFreeSubmenuSize,
                          submenuItems.count > limit,
                          submenuItems.allSatisfy({ $0.keys.isEmpty }) {
                    // Skip large shortcut-free submenus (e.g. browser history) to
                    // prevent them from flooding the popup in all-entries mode.
                } else {
                    named.append(ShortcutGroup(title: title, shortcuts: submenuItems))
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

    /// Recursively collects items within `menu`, flattening any nested submenus
    /// into a single list. Used for submenu contents (depth ≥ 2).
    /// Returns the shortcut list and the raw AX child count of `menu` so callers
    /// can log empty-submenu diagnostics without a second AX round-trip.
    private static func collectShortcutsFlat(
        in menu: AXUIElement, includeAll: Bool = false, depth: Int = 0,
        ignoredTitles: [String] = []
    ) -> (shortcuts: [Shortcut], rawChildCount: Int) {
        guard depth < 10 else { return ([], 0) }
        let menuChildren = children(menu)
        var result: [Shortcut] = []
        for item in menuChildren {
            let title = string(item, kAXTitleAttribute) ?? ""
            if title.isEmpty {
                result.append(.separator())
                continue
            }
            guard !IgnoreListStore.isIgnored(title: title, patterns: ignoredTitles) else { continue }

            let shortcutKeys = ShortcutFormatter.format(
                cmdChar:    string(item, kAXMenuItemCmdCharAttribute),
                virtualKey: int(item,    kAXMenuItemCmdVirtualKeyAttribute),
                glyph:      int(item,    kAXMenuItemCmdGlyphAttribute),
                modifiers:  int(item,    kAXMenuItemCmdModifiersAttribute) ?? 0
            )
            let submenu = children(item).first

            if let keys = shortcutKeys {
                result.append(Shortcut(title: title, keys: keys, axElement: item, isDisabled: false))
            } else if includeAll, submenu == nil {
                result.append(Shortcut(title: title, keys: "", axElement: item, isDisabled: false))
            }

            // Flatten sub-submenus.
            if let submenu {
                let (sub, subChildCount) = collectShortcutsFlat(in: submenu, includeAll: includeAll, depth: depth + 1, ignoredTitles: ignoredTitles)
                if sub.isEmpty {
                    let hint = subChildCount == 0 ? "; likely lazy-populated" : ""
                    Logger.scraper.info("Nested submenu '\(title, privacy: .private)' yielded 0 items (\(subChildCount, privacy: .public) child items\(hint, privacy: .private))")
                }
                result.append(contentsOf: sub)
            }
        }
        return (result, menuChildren.count)
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
        // CF types have no runtime type metadata so as?/as! both error in Xcode 26;
        // unsafeBitCast is safe here because CFGetTypeID guards above confirm the type.
        return unsafeBitCast(raw, to: AXUIElement.self)
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

// MARK: - UserDefaults

extension UserDefaults {
    private static let showAllMenuItemsKey = "showAllMenuItems"

    var showAllMenuItems: Bool {
        get { bool(forKey: Self.showAllMenuItemsKey) }
        set { set(newValue, forKey: Self.showAllMenuItemsKey) }
    }

    private static let requireFilterForAllMenuItemsKey = "requireFilterForAllMenuItems"

    var requireFilterForAllMenuItems: Bool {
        get { bool(forKey: Self.requireFilterForAllMenuItemsKey) }
        set { set(newValue, forKey: Self.requireFilterForAllMenuItemsKey) }
    }

    private static let hideLargeSubmenusKey = "hideLargeSubmenus"

    var hideLargeSubmenus: Bool {
        get { bool(forKey: Self.hideLargeSubmenusKey) }
        set { set(newValue, forKey: Self.hideLargeSubmenusKey) }
    }

    private static let showSystemShortcutsKey = "showSystemShortcuts"

    var showSystemShortcuts: Bool {
        get { bool(forKey: Self.showSystemShortcutsKey) }
        set { set(newValue, forKey: Self.showSystemShortcutsKey) }
    }

    private static let showDeactivatedSystemShortcutsKey = "showDeactivatedSystemShortcuts"

    var showDeactivatedSystemShortcuts: Bool {
        get { bool(forKey: Self.showDeactivatedSystemShortcutsKey) }
        set { set(newValue, forKey: Self.showDeactivatedSystemShortcutsKey) }
    }

    private static let showConflictIndicatorKey = "showConflictIndicator"

    var showConflictIndicator: Bool {
        get { bool(forKey: Self.showConflictIndicatorKey) }
        set { set(newValue, forKey: Self.showConflictIndicatorKey) }
    }

    private static let wrapLongSectionsKey = "wrapLongSections"

    var wrapLongSections: Bool {
        get { bool(forKey: Self.wrapLongSectionsKey) }
        set { set(newValue, forKey: Self.wrapLongSectionsKey) }
    }
}
