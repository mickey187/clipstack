import AppKit
import ClipStackCore
import SwiftUI

/// Shared state between the AppKit panel (which owns key handling) and the
/// SwiftUI list (which owns rendering).
@MainActor
@Observable
final class PopupModel {
    let store: ClipboardStore
    var selectedID: UUID?
    var hasAccessibility: Bool = true

    var onPaste: (ClipboardItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    init(store: ClipboardStore) {
        self.store = store
    }

    /// Pinned first, then the rest in recency order. This is the order the list
    /// renders and the order the keyboard navigates.
    var orderedItems: [ClipboardItem] {
        store.items.filter(\.isPinned) + store.items.filter { !$0.isPinned }
    }

    var pinnedItems: [ClipboardItem] { store.items.filter(\.isPinned) }
    var recentItems: [ClipboardItem] { store.items.filter { !$0.isPinned } }

    func resetSelection() {
        selectedID = orderedItems.first?.id
    }

    func moveSelection(by offset: Int) {
        let items = orderedItems
        guard !items.isEmpty else { return }
        guard let current = selectedID,
              let index = items.firstIndex(where: { $0.id == current }) else {
            selectedID = items.first?.id
            return
        }
        let next = min(max(index + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    func pasteSelected() {
        guard let id = selectedID,
              let item = orderedItems.first(where: { $0.id == id }) else { return }
        onPaste(item)
    }

    func paste(at position: Int) {
        let items = orderedItems
        guard position >= 0, position < items.count else { return }
        onPaste(items[position])
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        let items = orderedItems
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        store.remove(id: id)
        let remaining = orderedItems
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

/// Borderless floating panel. Overrides `canBecomeKey` so an accessory app can
/// still drive the list from the keyboard.
final class PopupPanel: NSPanel {
    var model: PopupModel?
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        guard let model else { return super.keyDown(with: event) }

        if event.modifierFlags.contains(.command),
           let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
           (1...9).contains(digit) {
            MainActor.assumeIsolated { model.paste(at: digit - 1) }
            return
        }

        switch Int(event.keyCode) {
        case 125: MainActor.assumeIsolated { model.moveSelection(by: 1) }
        case 126: MainActor.assumeIsolated { model.moveSelection(by: -1) }
        case 36, 76: MainActor.assumeIsolated { model.pasteSelected() }
        case 53: onDismiss?()
        case 51, 117: MainActor.assumeIsolated { model.deleteSelected() }
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
final class PopupPanelController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let model: PopupModel
    private var panel: PopupPanel!

    /// The app to paste back into, captured before we steal focus.
    private var targetApp: NSRunningApplication?

    private static let panelSize = NSSize(width: 340, height: 440)

    init(store: ClipboardStore) {
        self.store = store
        self.model = PopupModel(store: store)
        super.init()

        model.onPaste = { [weak self] item in self?.paste(item) }
        model.onDismiss = { [weak self] in self?.hide() }

        buildPanel()
    }

    private func buildPanel() {
        let panel = PopupPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.model = model
        panel.onDismiss = { [weak self] in self?.hide() }

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: PopupView(model: model))
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)

        panel.contentView = effect
        self.panel = panel
    }

    // MARK: - Show / hide

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        // Capture the paste target *before* we take focus.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApp = frontmost
        }

        model.hasAccessibility = Permissions.hasAccessibility
        model.resetSelection()

        panel.setFrameOrigin(originNearCursor())
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Top-left of the panel just below and right of the cursor, clamped on screen.
    private func originNearCursor() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.panelSize
        let inset: CGFloat = 8

        var x = mouse.x + 12
        var y = mouse.y - size.height - 12

        x = min(max(x, visible.minX + inset), visible.maxX - size.width - inset)
        y = min(max(y, visible.minY + inset), visible.maxY - size.height - inset)
        return NSPoint(x: x, y: y)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Paste

    private func paste(_ item: ClipboardItem) {
        hide()
        let target = targetApp
        Task { @MainActor in
            _ = await Paster.paste(item, store: self.store, into: target)
        }
    }
}
