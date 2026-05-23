import SwiftUI

@main
struct KeyMinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No standard windows: the UI lives in the menu bar status item and the
        // floating popup, both managed by AppDelegate.
        Settings { EmptyView() }
    }
}
