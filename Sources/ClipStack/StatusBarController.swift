import AppKit
import ClipStackCore

/// The menu bar presence: icon plus a minimal dropdown (PRD F8).
///
/// Left click opens the popup directly; right click (or click-and-hold) shows the menu,
/// so the common action stays one click away.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: ClipboardStore
    private let updates: UpdateChecker
    private let onOpen: () -> Void
    private let menu = NSMenu()

    init(store: ClipboardStore, updates: UpdateChecker, onOpen: @escaping () -> Void) {
        self.store = store
        self.updates = updates
        self.onOpen = onOpen
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: "ClipStack"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu.delegate = self
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onOpen()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Surfaced at the top only when there is genuinely something newer.
        if let version = updates.availableVersion {
            let update = NSMenuItem(
                title: "Update available (\(version))…",
                action: #selector(openReleases),
                keyEquivalent: ""
            )
            update.target = self
            menu.addItem(update)
            menu.addItem(.separator())
        }

        let open = NSMenuItem(title: "Open Clipboard", action: #selector(openPopup), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.option, .command]
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let count = store.items.count
        let status = NSMenuItem(
            title: count == 1 ? "1 item" : "\(count) items",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        if !Permissions.hasAccessibility {
            let warn = NSMenuItem(
                title: "Enable Accessibility to paste…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = count > 0
        menu.addItem(clear)

        let checkUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        let quit = NSMenuItem(title: "Quit ClipStack", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openPopup() { onOpen() }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func clearHistory() {
        store.clearAll()
        store.saveNow()
    }

    @objc private func openReleases() {
        updates.openReleasesPage()
    }

    @objc private func checkForUpdates() {
        updates.checkNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
