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
    private let license: LicenseManager
    private let onActivate: () -> Void
    private let onOpen: () -> Void
    private let panelSize: () -> PanelSize
    private let onPanelSize: (PanelSize) -> Void
    private let menu = NSMenu()

    init(
        store: ClipboardStore,
        updates: UpdateChecker,
        license: LicenseManager,
        onActivate: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        panelSize: @escaping () -> PanelSize,
        onPanelSize: @escaping (PanelSize) -> Void
    ) {
        self.store = store
        self.updates = updates
        self.license = license
        self.onActivate = onActivate
        self.onOpen = onOpen
        self.panelSize = panelSize
        self.onPanelSize = onPanelSize
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

        addLicensingItems(to: menu)

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

        menu.addItem(sizeMenuItem())

        if LoginItem.isSupported {
            let launch = NSMenuItem(
                title: "Start at Login",
                action: #selector(toggleLoginItem),
                keyEquivalent: ""
            )
            launch.target = self
            launch.state = LoginItem.isEnabled ? .on : .off
            menu.addItem(launch)

            if LoginItem.needsApproval {
                let approve = NSMenuItem(
                    title: "Approve ClipStack in Login Items…",
                    action: #selector(openLoginItemsSettings),
                    keyEquivalent: ""
                )
                approve.target = self
                menu.addItem(approve)
            }
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

    /// Panel size as a submenu: three fixed steps, the current one checked.
    private func sizeMenuItem() -> NSMenuItem {
        let current = panelSize()
        let submenu = NSMenu()
        for size in PanelSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(selectPanelSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = size == current ? .on : .off
            submenu.addItem(item)
        }

        let item = NSMenuItem(title: "Panel Size", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func openPopup() { onOpen() }

    @objc private func selectPanelSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = PanelSize(rawValue: raw) else { return }
        onPanelSize(size)
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openLoginItemsSettings() {
        LoginItem.openLoginItemsSettings()
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

    /// Trial countdown, or whatever needs sorting out. Nothing at all once someone has
    /// paid — a licensed user should never be reminded that licensing exists.
    private func addLicensingItems(to menu: NSMenu) {
        let entitlement = license.entitlement
        guard let title = entitlement.menuTitle else { return }

        let status = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let activate = NSMenuItem(
            title: "Activate Licence…",
            action: #selector(openActivation),
            keyEquivalent: ""
        )
        activate.target = self
        menu.addItem(activate)

        if !entitlement.isPaid {
            let buy = NSMenuItem(
                title: "Buy ClipStack — $12…",
                action: #selector(openCheckout),
                keyEquivalent: ""
            )
            buy.target = self
            menu.addItem(buy)
        }

        menu.addItem(.separator())
    }

    @objc private func openActivation() {
        onActivate()
    }

    @objc private func openCheckout() {
        NSWorkspace.shared.open(Checkout.purchaseURL)
    }
}
