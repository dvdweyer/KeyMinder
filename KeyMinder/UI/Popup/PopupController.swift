import AppKit
import SwiftUI

/// Owns the floating popup panel: builds its SwiftUI content, sizes and centers
/// it, and tears it down on any of the expected dismissal signals.
@MainActor
final class PopupController {

    /// Called when the onboarding "Grant Access" button is pressed.
    var onGrant: () -> Void = {}
    /// Called when the onboarding "Open Settings" button is pressed.
    var onOpenSettings: () -> Void = {}
    /// Called the moment `AXIsProcessTrusted()` becomes true while the
    /// onboarding screen is visible. AppDelegate should re-run its scrape/show
    /// path here so the popup refreshes with real shortcut content.
    var onPermissionGranted: () -> Void = {}

    private var panel: PopupPanel?
    private var eventMonitors: [Any] = []
    private var workspaceObserver: NSObjectProtocol?
    private let ownPID = NSRunningApplication.current.processIdentifier

    /// Live filter state for the current shortcuts presentation, if any. Read by
    /// the Esc handlers so Esc clears a non-empty filter before dismissing.
    private var filterModel: PopupFilterModel?

    /// Query from the most recently closed/replaced model and its app's bundle ID.
    /// Restored when the same app reopens so the filter persists across toggles.
    private var lastFilterQuery: String = ""
    private var lastFilterBundleID: String? = nil

    /// Shortcuts from ignored menus (e.g. Apple menu) for the current app.
    /// Not shown in the popup; used to trigger chord disambiguation.
    private var ignoredMenuShortcuts: [Shortcut] = []
    /// Display name of the frontmost app, used in the disambiguation overlay.
    private var currentAppName: String = ""

    // MARK: - Permission polling

    /// Fires every 0.5 s while the onboarding screen is visible and checks
    /// `AXIsProcessTrusted()`. Invalidated the moment trust is granted or the
    /// popup is hidden.
    private var permissionPollTimer: Timer?

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Animation state

    /// Monotonically-increasing generation token. Incremented on every show/hide
    /// call so that completion blocks from superseded animations are no-ops.
    private var animationGeneration = 0

    // MARK: - Show / hide

    /// Presents the panel with `content`, fading in over ~0.12 s.
    func show(_ content: PopupContent) {
        // Manage the permission-poll timer: run it only while the onboarding
        // screen is visible, and stop it the moment any other content is shown.
        if case .needsPermission = content {
            startPermissionPoll()
        } else {
            stopPermissionPoll()
        }

        if case .shortcuts(let app) = content {
            UserDefaults.standard.popupOpenCount += 1
            ignoredMenuShortcuts = app.ignoredMenuShortcuts
            currentAppName = app.appName
        }

        let panel = panel ?? makePanel()
        self.panel = panel

        apply(content, to: panel)

        // Invalidate any in-flight hide-fade completion so it won't orderOut.
        animationGeneration += 1

        // Start from invisible so the fade-in is perceptible.
        panel.alphaValue = 0

        // Prime a very subtle scale-up on the content layer (0.98 → 1.0).
        // NSHostingView is always layer-backed; we set the model value
        // immediately (no implicit animation) so it's in place before the
        // window appears, then animate it to identity alongside the fade.
        if let layer = panel.contentView?.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeScale(0.98, 0.98, 1.0)
            CATransaction.commit()
        }

        panel.makeKeyAndOrderFront(nil)
        installDismissalMonitors()

        // Fade in.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        // Scale to identity in parallel with the fade.
        if let layer = panel.contentView?.layer {
            let anim = CABasicAnimation(keyPath: "transform.scale")
            anim.fromValue = 0.98
            anim.toValue   = 1.0
            anim.duration  = 0.12
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "showScale")
            // Commit the model to identity with actions disabled so Core
            // Animation doesn't implicitly tween back to the from-value.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }

    /// Builds, sizes, and centers the hosting view for `content` on `panel`.
    private func apply(_ content: PopupContent, to panel: PopupPanel) {
        if let old = filterModel {
            lastFilterQuery = old.query
            lastFilterBundleID = old.app.bundleIdentifier
        }
        filterModel = nil
        let (hosting, size) = makeContent(for: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        let screen = Self.activeVisibleFrame
        let origin = CGPoint(x: screen.midX - size.width / 2,
                             y: screen.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// The visible frame of the screen the user is most likely working on:
    /// whichever display contains the mouse cursor, then the main screen, then
    /// the first screen in the list.
    ///
    /// Returns a geometry value rather than `NSScreen` so every fallback level
    /// is nil-safe.  `NSScreen.screens` can be momentarily empty during a
    /// display-reconfiguration event (e.g. connecting/disconnecting a monitor);
    /// the previous `NSScreen.screens[0]` subscript would crash in that window.
    /// If all three lookups return nil we fall back to a 1920×1080 sentinel at
    /// the origin, which is always large enough to safely centre the panel.
    private static var activeVisibleFrame: CGRect {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                     ?? NSScreen.main
                     ?? NSScreen.screens.first {
            return screen.visibleFrame
        }
        // No screen available during a display-reconfiguration race.
        // Use a conservative sentinel so the panel is positioned rather than crashing.
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    /// Fades the panel out over ~0.10 s and orders it out on completion.
    func hide() {
        // Remove monitors at the very start so a click-outside during the
        // fade doesn't re-trigger a second hide().
        removeDismissalMonitors()
        // Stop permission polling whenever the popup goes away.
        stopPermissionPoll()
        ignoredMenuShortcuts = []
        currentAppName = ""

        guard let panel else { return }

        animationGeneration += 1
        let generation = animationGeneration

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // The completion handler always fires on the main thread, so it's safe
            // to enter the main-actor domain to touch animationGeneration/panel.
            MainActor.assumeIsolated {
                // Guard against a show() that was called while we were fading out.
                // If generation differs, show() has already incremented it and
                // reclaimed self.panel — don't touch either.
                guard let self, generation == self.animationGeneration else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1   // Reset so the next show() fade starts clean.
                // Release the panel so the NSWindow, its hosting view, and all
                // SwiftUI state trees are deallocated while the popup is idle.
                // show() recreates it via makePanel() on the next open.
                self.panel = nil
            }
        }
    }

    // MARK: - Panel

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    // MARK: - Layout

    /// Builds the hosting view for `content` and the panel size to present it at.
    /// Non-shortcut states use fixed sizes; the shortcut grid keeps the analytic
    /// column/width math but *measures* its height from the real SwiftUI layout.
    private func makeContent(for content: PopupContent) -> (NSView, CGSize) {
        switch content {
        case .needsPermission:
            return fixedContent(content, size: CGSize(width: 420, height: 300))
        case .noApp:
            return fixedContent(content, size: CGSize(width: 360, height: 200))
        case .shortcuts(let app):
            guard !app.isEmpty else {
                return fixedContent(content, size: CGSize(width: 380, height: 200))
            }
            return measuredContent(content, app: app)
        }
    }

    /// Hosting view for the fixed-size states (onboarding, no app, empty app).
    private func fixedContent(_ content: PopupContent, size: CGSize) -> (NSView, CGSize) {
        let root = rootView(content, model: nil, width: size.width, height: size.height)
        return (NSHostingView(rootView: root), size)
    }

    /// Hosting view for the shortcut grid: column count and width come from the
    /// analytic layout, but the height is measured from the actual rendered
    /// content (no ScrollView), then clamped so the panel never exceeds the
    /// screen — overflow falls to the grid's own ScrollView.
    ///
    /// The panel is sized once here. In normal mode the layout is fixed for the
    /// life of the popup — rows dim but never move. In all-entries mode the
    /// panel is still sized for shortcuts only; no-shortcut items join the
    /// ScrollView when the filter query reaches two characters.
    private func measuredContent(_ content: PopupContent, app: AppShortcuts) -> (NSView, CGSize) {
        let screen = Self.activeVisibleFrame
        let maxPanelHeight = screen.height * 0.86

        // --- Column count + width. ---
        let horizontalBudget = screen.width * 0.96 - 2 * Theme.contentPadding
        let perColumn = MenuLayout.columnWidth + MenuLayout.columnSpacing
        let maxColumns = max(1, Int((horizontalBudget + MenuLayout.columnSpacing) / perColumn))

        // In all-entries mode, distribute columns using shortcuts-only section
        // heights so the panel is sized for the compact initial view. No-shortcut
        // items appear inside the ScrollView once the query reaches 2 characters.
        //
        // `shortcutsOnly` returns (layout, full) pairs so the mapping back to full
        // sections is by UUID rather than title — crash-safe for apps that happen to
        // have two top-level menus with the same title. If every item lacks a shortcut
        // the pairs are empty; fall back to self-paired full sections so the popup
        // still has content to display.
        var sectionPairs: [(layout: MenuSection, full: MenuSection)]
        if app.includesItemsWithoutShortcuts {
            let pairs = Self.shortcutsOnly(app.sections)
            sectionPairs = pairs.isEmpty
                ? app.sections.map { (layout: $0, full: $0) }
                : pairs
        } else {
            sectionPairs = app.sections.map { (layout: $0, full: $0) }
        }

        // When wrapping is on, split sections that exceed 60 % of the max panel
        // height into continuation pieces (same title, repeated header). The split
        // is applied to both layout and full independently so the UUID-keyed lookup
        // below still resolves correctly: each split piece gets a fresh UUID and
        // its own entry in the pairs array.
        if UserDefaults.standard.wrapLongSections {
            let maxColumnHeight = maxPanelHeight * 0.60
            sectionPairs = sectionPairs.flatMap { pair -> [(layout: MenuSection, full: MenuSection)] in
                let lPieces = MenuLayout.split([pair.layout], maxHeight: maxColumnHeight)
                let fPieces = MenuLayout.split([pair.full],   maxHeight: maxColumnHeight)
                // Use layout piece count as authoritative: each layout UUID must appear
                // exactly once in fullByID to avoid a crash from duplicate keys.
                // If full splits into more pieces the extra content merges into the
                // last layout piece's full counterpart (rare in practice).
                return lPieces.enumerated().map { i, l in
                    (layout: l, full: fPieces[min(i, fPieces.count - 1)])
                }
            }
        }

        let layoutSections = sectionPairs.map(\.layout)
        let count = min(layoutSections.count, maxColumns)
        let rawLayout = MenuLayout.distribute(layoutSections, columns: count)
        let distributedLayout = MenuLayout.consolidateTrailing(rawLayout)
        let actual = max(1, distributedLayout.count)

        let contentWidth = CGFloat(actual) * MenuLayout.columnWidth
            + CGFloat(actual - 1) * MenuLayout.columnSpacing
        let width = contentWidth + 2 * Theme.contentPadding

        // Map layout sections back to full sections by UUID (stable, unique by
        // construction — each MenuSection.id is a let UUID generated at init).
        let fullByID = Dictionary(uniqueKeysWithValues: sectionPairs.map { ($0.layout.id, $0.full) })
        let displayColumns: [[MenuSection]] = distributedLayout.map { col in
            col.compactMap { fullByID[$0.id] }
        }

        // Height is measured with an empty query. When "Only show when searching" is
        // off, showsAllItems is true here too — the measurement correctly captures the
        // taller all-entries height. When it is on, no-shortcut rows are absent.
        let placeholderModel = PopupFilterModel(app: app, columns: displayColumns)
        let measureView = rootView(content, model: placeholderModel, width: width,
                                   height: nil, scrolls: false)
        let measurer = NSHostingController(rootView: measureView)
        let naturalHeight = measurer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = min(naturalHeight, maxPanelHeight)

        // When all content fits without scrolling, filtering dims non-matching rows
        // rather than collapsing the layout, keeping column heights stable.
        let fitsWithoutScrolling = naturalHeight <= maxPanelHeight
        let model = PopupFilterModel(app: app, columns: displayColumns,
                                     fitsWithoutScrolling: fitsWithoutScrolling)
        // Don't restore the saved query when "show when filtering" is active:
        // ignored items should only be revealed by typing in the current session,
        // not by a query that happened to match them in a previous one.
        let ignoreStore = IgnoreListStore.shared
        let queryRestoreAllowed = !(ignoreStore.isEnabled && ignoreStore.showWhenFiltering)
        if queryRestoreAllowed, let bid = app.bundleIdentifier, bid == lastFilterBundleID {
            model.query = lastFilterQuery
        }
        model.heldModifiers = Self.extractModifiers(from: NSEvent.modifierFlags)
        filterModel = model

        let root = rootView(content, model: model, width: width,
                            height: height, scrolls: true)
        return (NSHostingView(rootView: root), CGSize(width: width, height: height))
    }

    /// Returns (layout, full) pairs for sections that contain at least one keyed
    /// shortcut. The layout copy holds only shortcuts with non-empty keys (for
    /// sizing); the full section is the original (for display). Pairing by value
    /// rather than title makes the caller's UUID-based lookup crash-safe when two
    /// top-level menus share a title.
    private static func shortcutsOnly(
        _ sections: [MenuSection]
    ) -> [(layout: MenuSection, full: MenuSection)] {
        sections.compactMap { section in
            let groups = section.groups.compactMap { group -> ShortcutGroup? in
                let shortcuts = group.shortcuts.filter { !$0.keys.isEmpty }
                return shortcuts.isEmpty ? nil : ShortcutGroup(title: group.title, shortcuts: shortcuts)
            }
            guard !groups.isEmpty else { return nil }
            return (layout: MenuSection(title: section.title, groups: groups), full: section)
        }
    }

    private func rootView(_ content: PopupContent,
                          model: PopupFilterModel?,
                          width: CGFloat,
                          height: CGFloat? = nil,
                          scrolls: Bool = true) -> PopupRootView {
        PopupRootView(
            content: content,
            model: model,
            width: width,
            height: height,
            scrolls: scrolls,
            onGrant: { [weak self] in self?.onGrant() },
            onOpenSettings: { [weak self] in self?.onOpenSettings() },
            onActivate: { [weak self] shortcut in self?.activate(shortcut) }
        )
    }

    // MARK: - Permission polling helpers

    /// Begins the 0.5 s poll for `AXIsProcessTrusted()`. No-op if already running.
    private func startPermissionPoll() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop; use assumeIsolated so the
            // compiler accepts main-actor property access inside the closure.
            MainActor.assumeIsolated {
                guard let self else { return }
                if AccessibilityPermission.isTrusted {
                    self.stopPermissionPoll()
                    self.onPermissionGranted()
                }
            }
        }
    }

    /// Stops and discards the permission-poll timer.
    private func stopPermissionPoll() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    // MARK: - Dismissal

    private func installDismissalMonitors() {
        removeDismissalMonitors()

        // Click anywhere outside our app dismisses.
        if let click = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in self?.hide() }
        ) {
            eventMonitors.append(click)
        }

        // Esc while frontmost (works because we have Accessibility permission).
        // Used when the panel isn't key; same clear-then-dismiss semantics.
        // Security: this callback receives ALL system-wide keyDown events while the popup
        // is visible. Only keyCode 53 (Esc) must ever be acted upon here — do not log,
        // store, or forward any other key event data.
        if let globalKey = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in if event.keyCode == 53 { _ = self?.handleEscape() } }
        ) {
            eventMonitors.append(globalKey)
        }

        // Key handling when the panel itself is key (e.g. the filter field has focus).
        // Esc clears the filter or dismisses; Tab advances/reverses the row selection;
        // Return activates the selected shortcut.
        if let localKey = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 53: // Esc
                    _ = self.handleEscape()
                    return nil
                case 48: // Tab
                    if event.modifierFlags.contains(.shift) {
                        self.filterModel?.selectPrevious()
                    } else {
                        self.filterModel?.selectNext()
                    }
                    return nil
                // case 2 where event.modifierFlags.contains(.command): // ⌘D — toggle favourite
                //     Disabled: ⌘ activates the command-key modifier filter before D is read.
                //     Planned replacement: long-press F (no modifier).
                case 36, 76: // Return / numpad Enter
                    if let shortcut = self.filterModel?.selectedShortcut {
                        self.activate(shortcut)
                        return nil
                    }
                    return event
                default:
                    // Chord invocation: ⌘ or ⌃ held + exactly one visible shortcut
                    // matches the key combo → invoke it directly.
                    let flags = event.modifierFlags
                    if flags.contains(.command) || flags.contains(.control) {
                        if let shortcut = self.matchShortcutEvent(event) {
                            self.activate(shortcut)
                            return nil
                        }
                        // No visible match — check shortcuts from ignored menus.
                        // If found, show disambiguation instead of falling through.
                        if let keysStr = ShortcutFormatter.keys(from: event),
                           !keysStr.isEmpty {
                            let candidates = self.ignoredMenuShortcuts.filter {
                                $0.keys == keysStr && $0.axElement != nil
                            }
                            if !candidates.isEmpty {
                                self.showDisambiguation(shortcuts: candidates, keys: keysStr)
                                return nil
                            }
                        }
                    }
                    return event
                }
            }
        ) {
            eventMonitors.append(localKey)
        }

        // Modifier key presses update the held-modifier filter in real time.
        // Global fires when another app is frontmost (normal case for this popup);
        // local fires when the popup panel itself is key (search field focused).
        if let flagsGlobal = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in self?.handleFlagsChanged(event) }
        ) {
            eventMonitors.append(flagsGlobal)
        }
        if let flagsLocal = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }
        ) {
            eventMonitors.append(flagsLocal)
        }

        // Switching to another app (e.g. via ⌘-Tab) dismisses.
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self, let app, app.processIdentifier != self.ownPID else { return }
            MainActor.assumeIsolated { self.hide() }
        }
    }

    /// Returns the unique visible shortcut whose `keys` string matches the key
    /// event, or `nil` when zero or multiple shortcuts match. Only shortcuts with
    /// an AX element (i.e. actionable) are considered.
    private func matchShortcutEvent(_ event: NSEvent) -> Shortcut? {
        guard let model = filterModel,
              let keysStr = ShortcutFormatter.keys(from: event),
              !keysStr.isEmpty else { return nil }
        let candidates = model.visibleShortcuts.filter {
            $0.keys == keysStr && $0.axElement != nil
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Dismisses the popup and fires the AX press action for `shortcut`.
    private func activate(_ shortcut: Shortcut) {
        let element = shortcut.axElement
        hide()
        if element != nil { ShortcutActivator.activate(shortcut) }
    }

    /// Shows the disambiguation overlay for `shortcuts` (from an ignored menu).
    private func showDisambiguation(shortcuts: [Shortcut], keys: String) {
        guard let model = filterModel else { return }
        let kmAction = KeyMinderActions.action(for: keys, onOpenSettings: { [weak self] in
            self?.onOpenSettings()
        })
        withAnimation {
            model.disambiguation = DisambiguationState(
                shortcuts: shortcuts,
                appName: currentAppName,
                keyMinderAction: kmAction
            )
        }
    }

    /// Esc behaviour: clear disambiguation first, then text filter, then toggled
    /// modifier filter, then favourites filter, then dismiss.
    @discardableResult
    private func handleEscape() -> Bool {
        if let filterModel, filterModel.disambiguation != nil {
            withAnimation { filterModel.disambiguation = nil }
            return true
        }
        if let filterModel, filterModel.hasQuery {
            filterModel.query = ""
            return true
        }
        if let filterModel, filterModel.hasToggledModifiers {
            filterModel.clearToggledModifiers()
            return true
        }
        if let filterModel, filterModel.showOnlyFavourites {
            filterModel.showOnlyFavourites = false
            return true
        }
        hide()
        return false
    }

    /// Updates `filterModel.heldModifiers` to reflect which modifier keys are
    /// currently pressed, as reported by a `flagsChanged` event.
    private func handleFlagsChanged(_ event: NSEvent) {
        guard let filterModel else { return }
        filterModel.heldModifiers = Self.extractModifiers(from: event.modifierFlags)
    }

    /// Returns the set of modifier glyphs currently held according to `flags`.
    private static func extractModifiers(from flags: NSEvent.ModifierFlags) -> Set<Character> {
        var held: Set<Character> = []
        if flags.contains(.command) { held.insert("⌘") }
        if flags.contains(.option)  { held.insert("⌥") }
        if flags.contains(.shift)   { held.insert("⇧") }
        if flags.contains(.control) { held.insert("⌃") }
        return held
    }

    private func removeDismissalMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }
}
