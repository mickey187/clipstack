import AppKit
import ApplicationServices

/// Accessibility permission, needed only for the synthetic ⌘V.
///
/// Everything else — the hotkey, capture, the popup — works without it, so a
/// missing grant degrades the app to "copied, press ⌘V yourself" rather than
/// failing silently.
@MainActor
enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt once per launch if we are not yet trusted.
    static func promptForAccessibilityIfNeeded() {
        guard !hasAccessibility else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
