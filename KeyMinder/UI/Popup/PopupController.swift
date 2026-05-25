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

    private var panel: PopupPanel?
    private var eventMonitors: [Any] = []
    private var workspaceObserver: NSObjectProtocol?
    private let ownPID = NSRunningApplication.current.processIdentifier

    /// Live filter state for the current shortcuts presentation, if any. Read by
    /// the Esc handlers so Esc clears a non-empty filter before dismissing.
    private var filterModel: PopupFilterModel?

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Show / hide

    /// Presents the panel with `content`.
    func show(_ content: PopupContent) {
        let panel = panel ?? makePanel()
        self.panel = panel

        apply(content, to: panel)
        panel.makeKeyAndOrderFront(nil)

        installDismissalMonitors()
    }

    /// Builds, sizes, and centers the hosting view for `content` on `panel`.
    private func apply(_ content: PopupContent, to panel: PopupPanel) {
        filterModel = nil
        let (hosting, size) = makeContent(for: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        let screen = Self.activeScreen.visibleFrame
        let origin = CGPoint(x: screen.midX - size.width / 2,
                             y: screen.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// The screen the user is most likely working on: whichever display contains
    /// the current mouse cursor, falling back to the main screen.
    private static var activeScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func hide() {
        removeDismissalMonitors()
        panel?.orderOut(nil)
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
    /// The panel is sized once here and the column distribution is fixed for the
    /// life of the popup. Live type-to-filter never changes the layout: every
    /// shortcut stays on screen in the same place; non-matching rows just dim.
    private func measuredContent(_ content: PopupContent, app: AppShortcuts) -> (NSView, CGSize) {
        let screen = Self.activeScreen.visibleFrame
        let maxPanelHeight = screen.height * 0.86

        // --- Column count + width. Spread menus across the available width:
        // as many columns as the screen fits, capped at one per menu. ---
        let horizontalBudget = screen.width * 0.96 - 2 * Theme.contentPadding
        let perColumn = MenuLayout.columnWidth + MenuLayout.columnSpacing
        let maxColumns = max(1, Int((horizontalBudget + MenuLayout.columnSpacing) / perColumn))

        let count = min(app.sections.count, maxColumns)
        let columns = MenuLayout.distribute(app.sections, columns: count)
        let actual = max(1, columns.count)

        let contentWidth = CGFloat(actual) * MenuLayout.columnWidth
            + CGFloat(actual - 1) * MenuLayout.columnSpacing
        let width = contentWidth + 2 * Theme.contentPadding

        let model = PopupFilterModel(app: app, columns: columns)
        filterModel = model

        // --- Height (measured from the real layout, no scroll wrapper). The
        // grid always renders the full content, so this measures it directly. ---
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
            onOpenSettings: { [weak self] in self?.onOpenSettings() }
        )
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
        if let globalKey = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in if event.keyCode == 53 { _ = self?.handleEscape() } }
        ) {
            eventMonitors.append(globalKey)
        }

        // Esc when the panel itself is key (e.g. the filter field has focus):
        // clear a non-empty filter first, otherwise dismiss. Either way the
        // keystroke is swallowed so it doesn't reach the filter field.
        if let localKey = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 53 {
                    _ = self.handleEscape()
                    return nil
                }
                return event
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
