import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let frontmostMonitor = FrontmostAppMonitor()
    private let popup = PopupController()
    private var statusItem: NSStatusItem?
    private var hintPopover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popup.onGrant = { AccessibilityPermission.requestAccess() }
        popup.onOpenSettings = { AccessibilityPermission.openSettings() }
        popup.onPermissionGranted = { [weak self] in
            self?.setupDoubleTap()
            self?.presentPopup()
        }
        setupStatusItem()
        setupHotkey()
        setupDoubleTap()
        setupSleepWakeObserver()
        showFirstLaunchSettingsIfNeeded()
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

    private func setupSleepWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // CGEventTaps can be silently invalidated on wake; re-arm the trigger.
            MainActor.assumeIsolated { self?.setupDoubleTap() }
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

    /// The background AX scrape itself. Stored so the next `presentPopup()` call
    /// can await it before starting a new traversal — `MenuScraper.scrape` is
    /// synchronous C AX IPC with no Swift cancellation checkpoints, so cancelling
    /// the outer task does not stop an in-flight scrape. Awaiting it first ensures
    /// at most one AX traversal runs at any time.
    private var detachedScrapeTask: Task<[MenuSection], Never>?

    /// Scrapes the frontmost app's menus off the main thread, then presents
    /// the popup with the result. The panel does not appear until data is ready.
    private func presentPopup() {
        dismissHint()
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
        let ignoredTitles = IgnoreListStore.shared.ignoredTitles(for: bundleID)

        // Cancel the outer coordinator so a stale result never reaches the UI.
        scrapeTask?.cancel()

        scrapeTask = Task {
            // If an AX traversal is already in flight, let it finish before
            // starting a new one — we can't cancel the synchronous C IPC, so
            // starting another would create concurrent traversals of the same app.
            // The result is discarded; we only wait to serialise access.
            if let previous = self.detachedScrapeTask {
                _ = await previous.value
                self.detachedScrapeTask = nil
            }

            // If we were cancelled while draining (another presentPopup fired),
            // stop here — the newer task will handle the scrape.
            guard !Task.isCancelled else { return }

            let work = Task.detached(priority: .userInitiated) {
                MenuScraper.scrape(pid: pid, includeItemsWithoutShortcuts: includeAll, ignoredTitles: ignoredTitles)
            }
            self.detachedScrapeTask = work

            let sections = await work.value
            self.detachedScrapeTask = nil

            guard !Task.isCancelled else { return }

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
        dismissHint()
        popup.hide()
        let menu = NSMenu()
        if !AccessibilityPermission.isTrusted {
            let grant = menu.addItem(withTitle: String(localized: "Grant Accessibility Access…"),
                                     action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(.separator())
        }
        // Discoverable hotkey row — shows the current shortcut (or "(unset)") so
        // users learn the keyboard trigger without having to open Settings.
        let hotkeyTitle: String
        if let hk = UserDefaults.standard.globalHotkey {
            hotkeyTitle = String(localized: "Show Shortcuts  \(hk.displayString)")
        } else {
            hotkeyTitle = String(localized: "Show Shortcuts  (unset)")
        }
        let hotkeyInfo = menu.addItem(withTitle: hotkeyTitle, action: nil, keyEquivalent: "")
        hotkeyInfo.isEnabled = false

        let settings = menu.addItem(withTitle: String(localized: "Settings…"),
                                    action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = .command

        let about = menu.addItem(withTitle: String(localized: "About KeyMinder"),
                                 action: #selector(showAbout), keyEquivalent: "")
        about.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: String(localized: "Quit KeyMinder"),
                                action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        // Show the menu on demand, then detach it so left-clicks still toggle.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let homepageURL = URL(string: "https://donald.van-de-weyer.net/keyminder.html")!

        let credits = NSMutableAttributedString(
            string: "Donald van de Weyer\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        let linkText = NSAttributedString(
            string: homepageURL.absoluteString,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: homepageURL,
                .foregroundColor: NSColor.linkColor,
            ]
        )
        credits.append(linkText)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: version,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func grantAccess() { AccessibilityPermission.requestAccess() }
    @objc private func openSettings() { SettingsWindowController.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - First-launch setup

    /// On the very first launch, opens Settings so the user can configure their
    /// preferred hotkey and double-tap trigger before using the app.
    /// When Settings is closed, a popover hint appears on the menu-bar icon.
    /// Subsequent launches are unaffected.
    private func showFirstLaunchSettingsIfNeeded() {
        guard !UserDefaults.standard.didShowWelcome else { return }
        UserDefaults.standard.didShowWelcome = true
        SettingsWindowController.onFirstClose = { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.showMenuBarHint()
            }
        }
        // Defer slightly so the status-bar item is visible before the window
        // appears (the run loop needs one pass to render the menu-bar icon).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            SettingsWindowController.show()
        }
    }

    private func showMenuBarHint() {
        guard let button = statusItem?.button else { return }
        let hotkey = UserDefaults.standard.globalHotkey?.displayString
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: MenuBarHintView(hotkey: hotkey)
        )
        popover.behavior = .applicationDefined
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hintPopover = popover
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.dismissHint()
        }
    }

    private func dismissHint() {
        hintPopover?.close()
        hintPopover = nil
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

// MARK: - First-launch hint view

private struct MenuBarHintView: View {
    let hotkey: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("KeyMinder is ready")
                    .font(.headline)
                if let hk = hotkey {
                    Text("Press \(hk) to show shortcuts for the active app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Click this icon to show shortcuts for the active app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
