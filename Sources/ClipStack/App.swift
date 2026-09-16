import AppKit
import ClipStackCore

@main
enum ClipStackApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Belt and braces alongside LSUIElement: no Dock icon, no app switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var statusBar: StatusBarController!
    private var hotkey: HotkeyManager!
    private var popup: PopupPanelController!
    private var updates: UpdateChecker!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipboardStore()
        store.load()

        popup = PopupPanelController(store: store)
        updates = UpdateChecker()
        statusBar = StatusBarController(
            store: store,
            updates: updates,
            onOpen: { [weak self] in self?.popup.toggle() }
        )

        monitor = ClipboardMonitor(store: store)
        monitor.start()

        hotkey = HotkeyManager()
        if !hotkey.register(keyCode: HotkeyManager.keyV, modifiers: [.option, .command], handler: { [weak self] in
            self?.popup.toggle()
        }) {
            NSLog("ClipStack: failed to register ⌥⌘V — another app may already own it.")
        }

        Permissions.promptForAccessibilityIfNeeded()
        updates.checkIfDue()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        store?.saveNow()
    }
}
