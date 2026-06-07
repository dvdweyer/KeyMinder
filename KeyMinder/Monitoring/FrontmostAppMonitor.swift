import AppKit
import Observation

/// Tracks the frontmost application, ignoring KeyMinder itself, so the popup can
/// always show shortcuts for the app the user was actually working in.
@MainActor
@Observable
final class FrontmostAppMonitor {

    private(set) var frontmostApp: NSRunningApplication?

    // nonisolated(unsafe): deinit is implicitly nonisolated and needs to
    // removeObserver; nonisolated alone errors on @Observable var (compiler bug).
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.update(app) }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Records the newly activated app, unless it is KeyMinder itself — in which
    /// case the previously recorded app is kept.
    private func update(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ownPID else { return }
        frontmostApp = app
    }
}
