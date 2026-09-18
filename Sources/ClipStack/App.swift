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
    private var license: LicenseManager!
    private var activation: ActivationWindowController!
    /// Keeps the trial's high water mark moving during a long session, so a clock
    /// wound back after hours of use gains nothing.
    private var clockHeartbeat: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipboardStore()
        store.load()

        license = LicenseManager(
            secrets: KeychainSecretStore(),
            defaults: LicenseDefaultsStore(),
            api: LicenseAPI(product: .clipStack, transport: URLSessionTransport.send),
            instanceName: "ClipStack — \(Host.current().localizedName ?? "Mac")"
        )
        license.start()

        activation = ActivationWindowController(
            license: license,
            onOpenCheckout: { NSWorkspace.shared.open(Checkout.purchaseURL) }
        )

        popup = PopupPanelController(
            store: store,
            license: license,
            onActivate: { [weak self] in self?.activation.show() }
        )
        updates = UpdateChecker()
        statusBar = StatusBarController(
            store: store,
            updates: updates,
            license: license,
            onActivate: { [weak self] in self?.activation.show() },
            onOpen: { [weak self] in self?.popup.toggle() },
            panelSize: { [weak self] in self?.popup.currentPanelSize ?? .default },
            onPanelSize: { [weak self] size in self?.popup.setPanelSize(size) }
        )

        monitor = ClipboardMonitor(
            store: store,
            // Fails open: if the manager has gone, capturing is the safer default.
            isCaptureAllowed: { [weak license] in license?.entitlement.capturesClipboard ?? true }
        )
        monitor.start()

        let heartbeat = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.license.observeClock() }
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        clockHeartbeat = heartbeat

        hotkey = HotkeyManager()
        if !hotkey.register(keyCode: HotkeyManager.keyV, modifiers: [.option, .command], handler: { [weak self] in
            self?.popup.toggle()
        }) {
            NSLog("ClipStack: failed to register ⌥⌘V — another app may already own it.")
        }

        Permissions.promptForAccessibilityIfNeeded()
        updates.checkIfDue()
        license.revalidateIfDue()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        clockHeartbeat?.invalidate()
        license?.persistTrialNow()
        store?.saveNow()
    }
}
