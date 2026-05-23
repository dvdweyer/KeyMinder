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

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Show / hide

    func show(_ content: PopupContent) {
        let (columns, size) = layout(for: content)
        let root = PopupRootView(
            content: content,
            columns: columns,
            size: size,
            onGrant: { [weak self] in self?.onGrant() },
            onOpenSettings: { [weak self] in self?.onOpenSettings() }
        )

        let panel = panel ?? makePanel()
        self.panel = panel

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: screen.midX - size.width / 2,
                             y: screen.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)

        installDismissalMonitors()
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

    private func layout(for content: PopupContent) -> (columns: [[MenuSection]], size: CGSize) {
        switch content {
        case .needsPermission:
            return ([], CGSize(width: 420, height: 300))
        case .noApp:
            return ([], CGSize(width: 360, height: 200))
        case .shortcuts(let app):
            guard !app.isEmpty else {
                return ([], CGSize(width: 380, height: 200))
            }
            let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let verticalChrome = 2 * Theme.contentPadding + 40
            let maxPanelHeight = screen.height * 0.86
            let maxColumnHeight = maxPanelHeight - verticalChrome

            let horizontalBudget = screen.width * 0.96 - 2 * Theme.contentPadding
            let perColumn = MenuLayout.columnWidth + MenuLayout.columnSpacing
            let maxColumns = max(1, Int((horizontalBudget + MenuLayout.columnSpacing) / perColumn))

            let count = MenuLayout.columnCount(for: app.sections,
                                               maxColumns: maxColumns,
                                               maxColumnHeight: maxColumnHeight)
            let columns = MenuLayout.distribute(app.sections, columns: count)
            let actual = max(1, columns.count)

            let contentWidth = CGFloat(actual) * MenuLayout.columnWidth
                + CGFloat(actual - 1) * MenuLayout.columnSpacing
            let width = contentWidth + 2 * Theme.contentPadding
            let tallest = MenuLayout.tallestColumnHeight(columns)
            let height = min(tallest + verticalChrome, maxPanelHeight)

            return (columns, CGSize(width: width, height: height))
        }
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
        if let globalKey = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in if event.keyCode == 53 { self?.hide() } }
        ) {
            eventMonitors.append(globalKey)
        }

        // Esc when the panel itself is key — swallow the event.
        if let localKey = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] event in
                if event.keyCode == 53 {
                    self?.hide()
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
