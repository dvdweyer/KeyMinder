import AppKit
import Sparkle
import SwiftUI

// Suppresses Sparkle's built-in first-run "check automatically?" dialog so the
// onboarding wizard (WelcomeLoginStep) is the single place this preference is set.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        return false
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.receiveBetaUpdates ? ["beta"] : []
    }
}

private struct PrecacheKey: Equatable {
    let pid: pid_t
    let includeAll: Bool
    let ignoredTitles: [String]
    let ignoredMenuTitles: [String]
    let maxSubmenuSize: Int?
}

private struct MenuCache {
    let key: PrecacheKey
    let sections: [MenuSection]
    let storedAt: Date
    static let ttl: TimeInterval = 20
    var isExpired: Bool { Date().timeIntervalSince(storedAt) > Self.ttl }
    func matches(_ k: PrecacheKey) -> Bool { !isExpired && key == k }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let frontmostMonitor = FrontmostAppMonitor()
    private let popup = PopupController()
    private let updaterDelegate = UpdaterDelegate()
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil
        )
    }()
    private var statusItem: NSStatusItem?
    private var hintPopover: NSPopover?
    private var betaChannelObserver: NSObjectProtocol?
    private var iconStyleObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popup.onGrant = { [weak self] in
            self?.popup.hide()
            AccessibilityPermission.requestAccess()
        }
        popup.onOpenSettings = { [weak self] in
            self?.popup.hide()
            SettingsWindowController.show()
        }
        popup.onPermissionGranted = { [weak self] in
            self?.setupDoubleTap()
            self?.presentPopup()
        }
        frontmostMonitor.onAppChanged = { [weak self] app in
            self?.precacheMenus(for: app)
        }
        setupStatusItem()
        setupHotkey()
        setupDoubleTap()
        setupSleepWakeObserver()
        showWelcomeIfNeeded()
        betaChannelObserver = NotificationCenter.default.addObserver(
            forName: .receiveBetaUpdatesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updaterController.updater.resetUpdateCycleAfterShortDelay()
            }
        }
        iconStyleObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconStyleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMenuBarIcon()
            }
        }
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
            button.image = UserDefaults.standard.menuBarIconStyle.makeImage()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private func updateMenuBarIcon() {
        statusItem?.button?.image = UserDefaults.standard.menuBarIconStyle.makeImage()
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
    /// at most one AX traversal runs at any time. Also used for pre-cache tasks
    /// started on app switch (at .utility priority).
    private var detachedScrapeTask: Task<[MenuSection], Never>?
    /// Params the current `detachedScrapeTask` was started with (nil for user-triggered scrapes).
    private var preCacheKey: PrecacheKey?
    /// Most-recent completed scrape result; checked before starting a fresh scrape.
    private var menuCache: MenuCache?

    /// Scrapes the frontmost app's menus off the main thread, then presents
    /// the popup with the result. The panel does not appear until data is ready.
    private func presentPopup() {
        dismissHint()
        guard AccessibilityPermission.isTrusted else {
            popup.show(.needsPermission)
            return
        }
        guard let app = frontmostMonitor.frontmostApp else {
            if UserDefaults.standard.showSystemShortcuts,
               let sys = SystemShortcutsProvider.load() {
                let icon = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)
                let shortcuts = AppShortcuts(
                    appName: String(localized: "System"),
                    bundleIdentifier: "__system__",
                    icon: icon,
                    sections: [sys],
                    includesItemsWithoutShortcuts: false
                )
                popup.show(.shortcuts(shortcuts))
            } else {
                popup.show(.noApp)
            }
            return
        }

        // Capture everything the scrape needs from the main actor up front; only
        // value types cross to the background task.
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "App"
        let bundleID = app.bundleIdentifier
        let icon = app.icon
        let includeAll = UserDefaults.standard.showAllMenuItems
        let maxSubmenuSize: Int? = (includeAll && UserDefaults.standard.hideLargeSubmenus) ? 5 : nil
        let ignoreStore = IgnoreListStore.shared
        guard !ignoreStore.isAppIgnored(bundleID) else { return }
        let ignoredTitles: [String] = (ignoreStore.isEnabled && !ignoreStore.showWhenFiltering)
            ? ignoreStore.ignoredTitles(for: bundleID)
            : []
        let ignoredMenuTitles = ignoreStore.ignoredMenuTitles

        let cacheKey = PrecacheKey(pid: pid, includeAll: includeAll,
                                   ignoredTitles: ignoredTitles, ignoredMenuTitles: ignoredMenuTitles,
                                   maxSubmenuSize: maxSubmenuSize)

        // Cancel the outer coordinator so a stale result never reaches the UI.
        scrapeTask?.cancel()

        scrapeTask = Task {
            // Drain any in-flight AX traversal before starting a new one.
            // If it was a pre-cache for exactly this invocation, keep the result.
            if let previous = self.detachedScrapeTask {
                let drained = await previous.value
                self.detachedScrapeTask = nil
                if self.preCacheKey == cacheKey {
                    self.menuCache = MenuCache(key: cacheKey, sections: drained, storedAt: Date())
                }
                self.preCacheKey = nil
            }

            // If we were cancelled while draining (another presentPopup fired),
            // stop here — the newer task will handle the scrape.
            guard !Task.isCancelled else { return }

            // Use the cache if it's fresh and matches this invocation's settings.
            let sections: [MenuSection]
            if let hit = self.menuCache, hit.matches(cacheKey) {
                sections = hit.sections
            } else {
                let work = Task.detached(priority: .userInitiated) {
                    MenuScraper.scrape(pid: pid, includeItemsWithoutShortcuts: includeAll,
                                       ignoredTitles: ignoredTitles, ignoredMenuTitles: ignoredMenuTitles,
                                       maxShortcutFreeSubmenuSize: maxSubmenuSize)
                }
                self.detachedScrapeTask = work
                sections = await work.value
                self.detachedScrapeTask = nil
                self.menuCache = MenuCache(key: cacheKey, sections: sections, storedAt: Date())
            }

            guard !Task.isCancelled else { return }

            var allSections = sections
            if UserDefaults.standard.showSystemShortcuts,
               let sys = SystemShortcutsProvider.load() {
                allSections.append(sys)
            }
            let shortcuts = AppShortcuts(
                appName: appName,
                bundleIdentifier: bundleID,
                icon: icon,
                sections: allSections,
                includesItemsWithoutShortcuts: includeAll
            )
            popup.show(.shortcuts(shortcuts))
        }
    }

    // MARK: - Pre-cache

    /// Starts a background AX scrape at .utility priority when an app becomes
    /// frontmost, so the result is ready (or nearly ready) when the user invokes
    /// the popup. Stores the result in `menuCache`; `presentPopup()` skips the
    /// scrape entirely on a cache hit.
    private func precacheMenus(for app: NSRunningApplication) {
        guard AccessibilityPermission.isTrusted else { return }
        guard !UserDefaults.standard.showAllMenuItems else { return }
        let ignoreStore = IgnoreListStore.shared
        guard !ignoreStore.isAppIgnored(app.bundleIdentifier) else { return }

        let pid = app.processIdentifier
        let ignoredTitles: [String] = ignoreStore.isEnabled && !ignoreStore.showWhenFiltering
            ? ignoreStore.ignoredTitles(for: app.bundleIdentifier) : []
        let ignoredMenuTitles = ignoreStore.ignoredMenuTitles
        let key = PrecacheKey(pid: pid, includeAll: false,
                              ignoredTitles: ignoredTitles, ignoredMenuTitles: ignoredMenuTitles,
                              maxSubmenuSize: nil)

        // Evict cache from the previous app.
        if menuCache?.key.pid != pid { menuCache = nil }

        // Nothing to do if a fresh cache already exists or a task is running.
        if menuCache?.matches(key) == true || detachedScrapeTask != nil { return }

        preCacheKey = key
        detachedScrapeTask = Task.detached(priority: .utility) {
            MenuScraper.scrape(pid: pid, ignoredTitles: ignoredTitles, ignoredMenuTitles: ignoredMenuTitles)
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

        let checkUpdates = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdates.target = updaterController
        menu.addItem(checkUpdates)

        if AccessibilityPermission.isTrusted, frontmostMonitor.frontmostApp != nil {
            let quiz = menu.addItem(withTitle: String(localized: "Quiz Mode…"),
                                    action: #selector(startQuiz), keyEquivalent: "")
            quiz.target = self
        }

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

    @objc private func startQuiz() {
        guard let app = frontmostMonitor.frontmostApp else { return }
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "App"
        let appIcon = app.icon
        let bundleID = app.bundleIdentifier
        Task {
            let sections = await Task.detached(priority: .userInitiated) {
                MenuScraper.scrape(pid: pid)
            }.value
            QuizWindowController.show(appName: appName, appIcon: appIcon, bundleID: bundleID, sections: sections)
        }
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let channel = Bundle.main.object(forInfoDictionaryKey: "KMReleaseChannel") as? String ?? ""
        let displayVersion = channel.isEmpty ? version : "\(version)-\(channel)"
        let homepageURL = URL(string: "https://keyminder.app/")!

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
        credits.append(NSAttributedString(
            string: "\nFeedback: ",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        ))
        let feedbackURL = URL(string: "mailto:keyminder@afaik.org")!
        credits.append(NSAttributedString(
            string: "keyminder@afaik.org",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: feedbackURL,
                .foregroundColor: NSColor.linkColor,
            ]
        ))

        let windowsBefore = Set(NSApp.windows)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: displayVersion,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)

        if let aboutWindow = NSApp.windows.first(where: { !windowsBefore.contains($0) }) {
            DockIconManager.shared.windowOpened()
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: aboutWindow,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { DockIconManager.shared.windowClosed() }
                NotificationCenter.default.removeObserver(observer!)
            }
        }
    }

    @objc private func grantAccess() { AccessibilityPermission.requestAccess() }
    @objc private func openSettings() { SettingsWindowController.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - First-launch setup

    /// On the very first launch, shows the welcome wizard so the user can grant
    /// Accessibility access and configure a trigger before seeing the popup.
    /// Subsequent launches are unaffected.
    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.didShowOnboardingWizard else { return }
        WelcomeWindowController.shared.onTryItNow = { [weak self] in
            self?.presentPopup()
        }
        WelcomeWindowController.shared.onComplete = { [weak self] in
            UserDefaults.standard.didShowOnboardingWizard = true
            UserDefaults.standard.onboardingResumeStep = nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                // Reinstall event monitors now that Accessibility is granted.
                // setupDoubleTap() at launch ran before the grant and got nil
                // monitors; this is the first opportunity to install them properly.
                self?.setupDoubleTap()
                self?.showMenuBarHint()
                if AXIsProcessTrusted() { self?.presentPopup() }
            }
        }
        // Defer one run-loop pass so the status-bar item is rendered before
        // the window appears.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            WelcomeWindowController.shared.show()
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

// MARK: - UserDefaults: onboarding flag

private extension UserDefaults {
    private static let didShowOnboardingWizardKey = "didShowOnboardingWizard"

    /// `true` once the welcome wizard has been shown. Uses a distinct key from
    /// the legacy `didShowWelcome` (which was set by the old Settings-on-launch
    /// flow) so that all existing users see the new wizard on first upgrade.
    var didShowOnboardingWizard: Bool {
        get { bool(forKey: Self.didShowOnboardingWizardKey) }
        set { set(newValue, forKey: Self.didShowOnboardingWizardKey) }
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
