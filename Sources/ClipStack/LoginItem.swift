import AppKit
import Foundation
import ServiceManagement

/// Start-at-login, via `SMAppService.mainApp` — the modern replacement for a
/// bundled LaunchAgent, so there is nothing extra to ship in the bundle.
///
/// State is always read back from `status` rather than cached: a registration can
/// be revoked in System Settings behind our back, and a stale checkmark on a menu
/// item is worse than no menu item.
@MainActor
enum LoginItem {
    /// Registration needs a real bundle. Under `swift run` there is none, so the
    /// menu item is hidden rather than offered and broken.
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The user switched it off in System Settings. Re-registering does not undo
    /// that, so the only honest move is to send them back there.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Never throws at the UI: a failed toggle is a no-op that the next menu
    /// opening reports correctly, because the checkmark comes from `status`.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginLog.error("login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func openLoginItemsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
