import ServiceManagement

/// Wraps `SMAppService.mainApp` to register / unregister KeyMinder as a login item.
///
/// `SMAppService` is available on macOS 13+; since KeyMinder targets macOS 26+ this
/// is always available without any availability guard.
@MainActor
final class LoginItemManager {

    static let shared = LoginItemManager()
    private init() {}

    /// `true` when the app is currently registered as a login item.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    /// Throws an `SMAppService` error if the system call fails.
    func setEnabled(_ enable: Bool) throws {
        if enable {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
