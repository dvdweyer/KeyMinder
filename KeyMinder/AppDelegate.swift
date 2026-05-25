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
        setupHotkey()
        setupDoubleTap()
    }

    // MARK: - Global hotkey

    private func setupHotkey() {
        HotkeyManager.shared.onActivate = { [weak self] in self?.togglePopup() }

        // First-launch seeding: apply ⌥⌘K as the default hotkey the very first
        // time the app runs, but only when the user has not already configured
        // (or deliberately cleared) a hotkey.  The flag is set unconditionally so
        // we never re-seed after the user removes their hotkey.
        if !UserDefaults.standard.didSetDefaultHotkey {
            UserDefaults.standard.didSetDefaultHotkey = true
            if UserDefaults.standard.globalHotkey == nil {
                let def = GlobalHotkey.defaultHotkey
                UserDefaults.standard.globalHotkey = def
                HotkeyManager.shared.register(def)
                return
            }
        }

        if let saved = UserDefaults.standard.globalHotkey {
            HotkeyManager.shared.register(saved)
        }
    }

    // MARK: - Double-tap trigger

    private func setupDoubleTap() {
        DoubleTapTrigger.shared.onActivate = { [weak self] in self?.togglePopup() }
        if UserDefaults.standard.doubleTapEnabled {
            DoubleTapTrigger.shared.start(modifier: UserDefaults.standard.doubleTapModifier)
        }
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
            presentPopup()
        }
    }

    /// In-flight scrape task. Cancelled if the user triggers another open
    /// before the previous scrape finishes.
    private var scrapeTask: Task<Void, Never>?

    /// Scrapes the frontmost app's menus off the main thread, then presents
    /// the popup with the result. The panel does not appear until data is ready.
    private func presentPopup() {
        guard AccessibilityPermission.isTrusted else {
            popup.show(.needsPermission)
            return
        }
        guard let app = frontmostMonitor.frontmostApp else {
            popup.show(.noApp)
            return
        }

        // Capture everything the scrape needs from the main actor up front; only
        // the pid crosses to the background task.
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "App"
        let bundleID = app.bundleIdentifier
        let icon = app.icon

        // Cancel any stale in-flight scrape before starting a new one.
        scrapeTask?.cancel()
        scrapeTask = Task {
            let sections = await Task.detached(priority: .userInitiated) {
                MenuScraper.scrape(pid: pid)
            }.value

            guard !Task.isCancelled else { return }

            let shortcuts = AppShortcuts(
                appName: appName,
                bundleIdentifier: bundleID,
                icon: icon,
                sections: sections
            )
            popup.show(.shortcuts(shortcuts))
        }
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
        // Discoverable hotkey row — shows the current shortcut (or "(unset)") so
        // users learn the keyboard trigger without having to open Settings.
        let hotkeyTitle: String
        if let hk = UserDefaults.standard.globalHotkey {
            hotkeyTitle = "Show Shortcuts  \(hk.displayString)"
        } else {
            hotkeyTitle = "Show Shortcuts  (unset)"
        }
        let hotkeyInfo = menu.addItem(withTitle: hotkeyTitle, action: nil, keyEquivalent: "")
        hotkeyInfo.isEnabled = false

        let settings = menu.addItem(withTitle: "Settings…",
                                    action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = .command

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit KeyMinder",
                                action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        // Show the menu on demand, then detach it so left-clicks still toggle.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func grantAccess() { AccessibilityPermission.requestAccess() }
    @objc private func openSettings() { SettingsWindowController.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
