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
        popup.onPermissionGranted = { [weak self] in self?.presentPopup() }
        setupStatusItem()
        setupHotkey()
        setupDoubleTap()
        showWelcomePopupIfNeeded()
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

    /// Outer coordinator task. Cancelled when a new presentPopup() fires while
    /// a scrape is already in flight.
    private var scrapeTask: Task<Void, Never>?

    /// The background AX scrape itself. Stored separately so it can be
    /// cancelled before the next scrape starts, preventing multiple concurrent
    /// AX traversals from accumulating on rapid toggling.
    ///
    /// Note: MenuScraper.scrape(pid:) is synchronous C AX IPC with no Swift
    /// cancellation checkpoints, so the cancelled task still runs to its first
    /// natural exit. The main benefit is that at most one scrape is in flight
    /// at a time once any previous scrapeTask is cancelled.
    private var detachedScrapeTask: Task<[MenuSection], Never>?

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
        // value types cross to the background task.
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "App"
        let bundleID = app.bundleIdentifier
        let icon = app.icon
        let includeAll = UserDefaults.standard.showAllMenuItems

        // Cancel any stale in-flight scrapes before starting new ones.
        scrapeTask?.cancel()
        detachedScrapeTask?.cancel()

        let work = Task.detached(priority: .userInitiated) {
            MenuScraper.scrape(pid: pid, includeItemsWithoutShortcuts: includeAll)
        }
        detachedScrapeTask = work

        scrapeTask = Task {
            let sections = await work.value

            // When this outer task has been cancelled (because presentPopup()
            // was called again), `detachedScrapeTask` already points to the
            // newer work — don't touch it.  Only clear on the success path
            // where we know we are still the active scrape.
            guard !Task.isCancelled else { return }
            detachedScrapeTask = nil

            let shortcuts = AppShortcuts(
                appName: appName,
                bundleIdentifier: bundleID,
                icon: icon,
                sections: sections,
                includesItemsWithoutShortcuts: includeAll
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

    // MARK: - First-launch welcome

    /// On the very first launch, auto-presents the popup once so the user
    /// discovers what KeyMinder does without having to find the status-bar icon
    /// themselves. Subsequent launches are unaffected.
    private func showWelcomePopupIfNeeded() {
        guard !UserDefaults.standard.didShowWelcome else { return }
        UserDefaults.standard.didShowWelcome = true
        // Defer slightly so the status-bar item is visible before the popup
        // appears (the run loop needs one pass to render the menu-bar icon).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            presentPopup()
        }
    }
}

// MARK: - UserDefaults: first-launch flag

private extension UserDefaults {
    private static let didShowWelcomeKey = "didShowWelcome"

    /// `true` after the welcome popup has been shown at least once.
    var didShowWelcome: Bool {
        get { bool(forKey: Self.didShowWelcomeKey) }
        set { set(newValue, forKey: Self.didShowWelcomeKey) }
    }
}
