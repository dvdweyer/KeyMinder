import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let frontmostMonitor = FrontmostAppMonitor()
    private let popup = PopupController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popup.onGrant = { AccessibilityPermission.requestAccess() }
        popup.onOpenSettings = { AccessibilityPermission.openSettings() }
        setupStatusItem()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyMinder")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showContextMenu()
        } else {
            togglePopup()
        }
    }

    private func togglePopup() {
        if popup.isVisible {
            popup.hide()
        } else {
            popup.show(currentContent())
        }
    }

    /// Builds the popup content for the current state, scraping the frontmost app.
    private func currentContent() -> PopupContent {
        guard AccessibilityPermission.isTrusted else { return .needsPermission }
        guard let app = frontmostMonitor.frontmostApp else { return .noApp }
        let sections = MenuScraper.scrape(pid: app.processIdentifier)
        return .shortcuts(AppShortcuts(
            appName: app.localizedName ?? "App",
            bundleIdentifier: app.bundleIdentifier,
            icon: app.icon,
            sections: sections
        ))
    }

    // MARK: - Context menu (right-click)

    private func showContextMenu() {
        popup.hide()
        let menu = NSMenu()
        if !AccessibilityPermission.isTrusted {
            let grant = menu.addItem(withTitle: "Grant Accessibility Access…",
                                     action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(.separator())
        }
        let quit = menu.addItem(withTitle: "Quit KeyMinder",
                                action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        // Show the menu on demand, then detach it so left-clicks still toggle.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func grantAccess() { AccessibilityPermission.requestAccess() }
    @objc private func quit() { NSApp.terminate(nil) }
}
