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
        let layoutSections = app.includesItemsWithoutShortcuts
            ? Self.shortcutsOnly(app.sections)
            : app.sections

        let count = min(layoutSections.count, maxColumns)
        let distributedLayout = MenuLayout.distribute(layoutSections, columns: count)
        let actual = max(1, distributedLayout.count)

        let contentWidth = CGFloat(actual) * MenuLayout.columnWidth
            + CGFloat(actual - 1) * MenuLayout.columnSpacing
        let width = contentWidth + 2 * Theme.contentPadding

        // Map the shortcuts-only column assignment back to full sections so that
        // no-shortcut items are present in the model and can appear on demand.
        let fullByTitle = Dictionary(uniqueKeysWithValues: app.sections.map { ($0.title, $0) })
        let displayColumns: [[MenuSection]] = distributedLayout.map { col in
            col.compactMap { fullByTitle[$0.title] }
        }

        let model = PopupFilterModel(app: app, columns: displayColumns)
        filterModel = model

        // Height is measured with an empty query, so showsAllItems is false and
        // no-shortcut rows are absent from the layout — giving the compact
        // shortcuts-only height.
        let measureView = rootView(content, model: model, width: width,
                                   height: nil, scrolls: false)
        let measurer = NSHostingView(rootView: measureView)
        measurer.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        measurer.layoutSubtreeIfNeeded()
        let naturalHeight = measurer.fittingSize.height
        let height = min(naturalHeight, maxPanelHeight)

        let root = rootView(content, model: model, width: width,
                            height: height, scrolls: true)
        return (NSHostingView(rootView: root), CGSize(width: width, height: height))
    }

    /// Returns a copy of `sections` containing only shortcuts (non-empty keys),
    /// dropping empty groups and sections. Used for column distribution and panel
    /// sizing in all-entries mode so the popup opens at shortcuts-only dimensions.
    private static func shortcutsOnly(_ sections: [MenuSection]) -> [MenuSection] {
        sections.compactMap { section in
            let groups = section.groups.compactMap { group -> ShortcutGroup? in
                let shortcuts = group.shortcuts.filter { !$0.keys.isEmpty }
                return shortcuts.isEmpty ? nil : ShortcutGroup(title: group.title, shortcuts: shortcuts)
            }
            return groups.isEmpty ? nil : MenuSection(title: section.title, groups: groups)
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
                case 36, 76: // Return / numpad Enter
                    if let shortcut = self.filterModel?.selectedShortcut {
                        self.activate(shortcut)
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
        ) {
            eventMonitors.append(localKey)
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

    /// Dismisses the popup and fires the AX press action for `shortcut`.
    private func activate(_ shortcut: Shortcut) {
        let element = shortcut.axElement
        hide()
        if element != nil { ShortcutActivator.activate(shortcut) }
    }

    /// Esc behaviour: clear a non-empty filter (keeping the popup open), or
    /// dismiss the popup when there's nothing to clear. Returns `true` when it
    /// only cleared the filter.
    @discardableResult
    private func handleEscape() -> Bool {
        if let filterModel, filterModel.hasQuery {
            filterModel.query = ""
            return true
        }
        hide()
        return false
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
