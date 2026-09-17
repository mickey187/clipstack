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

    /// Drives both the panel frame and the type scale inside it. Owned by the
    /// model so the SwiftUI tree redraws at the new scale the moment it changes.
    var panelSize: PanelSize = .default

    /// Search and category are view state, cleared on every open, so ⌥⌘V always
    /// lands on the whole history rather than on whatever you filtered to last.
    var searchQuery: String = ""
    var category: ItemCategory = .all

    var onPaste: (ClipboardItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    init(store: ClipboardStore, panelSize: PanelSize) {
        self.store = store
        self.panelSize = panelSize
    }

    var isFiltering: Bool { !searchQuery.isEmpty || category != .all }

    /// Everything the current filter allows through, newest first.
    var visibleItems: [ClipboardItem] {
        store.items.filtered(category: category, query: searchQuery)
    }

    /// Pinned first, then the rest in recency order. This is the order the list
    /// renders and the order the keyboard navigates — so rooting it on
    /// `visibleItems` is what makes ↑/↓, ⏎ and ⌘1–9 follow the filter.
    var orderedItems: [ClipboardItem] {
        let visible = visibleItems
        return visible.filter(\.isPinned) + visible.filter { !$0.isPinned }
    }

    var pinnedItems: [ClipboardItem] { visibleItems.filter(\.isPinned) }
    var recentItems: [ClipboardItem] { visibleItems.filter { !$0.isPinned } }

    func resetSelection() {
        selectedID = orderedItems.first?.id
    }

    // MARK: - Filtering

    func appendToQuery(_ characters: String) {
        searchQuery += characters
        repairSelection()
    }

    func deleteLastQueryCharacter() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        repairSelection()
    }

    func clearFilters() {
        searchQuery = ""
        category = .all
        repairSelection()
    }

    func select(category: ItemCategory) {
        self.category = category
        repairSelection()
    }

    func cycleCategory(by offset: Int) {
        let all = ItemCategory.allCases
        guard let index = all.firstIndex(of: category) else { return }
        category = all[((index + offset) % all.count + all.count) % all.count]
        repairSelection()
    }

    /// Keeps the selection on something still on screen after a filter change,
    /// so ⏎ can never paste a row the list is no longer showing.
    private func repairSelection() {
        let items = orderedItems
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return }
        selectedID = items.first?.id
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

        // ⌘⌫ stays a delete even while a search is being typed, since bare ⌫
        // belongs to the query at that point.
        if event.modifierFlags.contains(.command), Int(event.keyCode) == 51 {
            MainActor.assumeIsolated { model.deleteSelected() }
            return
        }

        switch Int(event.keyCode) {
        case 125: MainActor.assumeIsolated { model.moveSelection(by: 1) }
        case 126: MainActor.assumeIsolated { model.moveSelection(by: -1) }
        case 36, 76: MainActor.assumeIsolated { model.pasteSelected() }
        case 48: // ⇥ / ⇧⇥ walks the category chips.
            let back = event.modifierFlags.contains(.shift)
            MainActor.assumeIsolated { model.cycleCategory(by: back ? -1 : 1) }
        case 53:
            // Two-stage: ⎋ undoes the filter first, so it never closes the popup
            // out from under a search.
            if MainActor.assumeIsolated({ model.isFiltering }) {
                MainActor.assumeIsolated { model.clearFilters() }
            } else {
                onDismiss?()
            }
        case 51:
            MainActor.assumeIsolated {
                if model.searchQuery.isEmpty {
                    model.deleteSelected()
                } else {
                    model.deleteLastQueryCharacter()
                }
            }
        case 117: MainActor.assumeIsolated { model.deleteSelected() }
        default:
            if let typed = Self.typedCharacters(in: event) {
                MainActor.assumeIsolated { model.appendToQuery(typed) }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// The printable text of an unmodified keystroke — the type-to-search input.
    ///
    /// Anything carrying ⌘/⌃/⌥ or coming off the function-key row is a command,
    /// not typing, and is handed back to AppKit.
    private static func typedCharacters(in event: NSEvent) -> String? {
        let ignored: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        guard event.modifierFlags.isDisjoint(with: ignored) else { return nil }
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        guard characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return characters
    }
}

@MainActor
final class PopupPanelController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let model: PopupModel
    private var panel: PopupPanel!

    /// The app to paste back into, captured before we steal focus.
    private var targetApp: NSRunningApplication?

    private var panelSize: NSSize {
        NSSize(width: model.panelSize.width, height: model.panelSize.height)
    }

    init(store: ClipboardStore) {
        self.store = store
        self.model = PopupModel(store: store, panelSize: Preferences.panelSize)
        super.init()

        model.onPaste = { [weak self] item in self?.paste(item) }
        model.onDismiss = { [weak self] in self?.hide() }

        buildPanel()
    }

    private func buildPanel() {
        let panel = PopupPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
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

    // MARK: - Size

    /// Applies a new size step and remembers it. Resizes in place when the panel
    /// is already open, so the choice is visible immediately rather than at the
    /// next ⌥⌘V.
    func setPanelSize(_ size: PanelSize) {
        guard size != model.panelSize else { return }
        model.panelSize = size
        Preferences.panelSize = size

        panel.setContentSize(panelSize)
        if panel.isVisible {
            panel.setFrameOrigin(originNearCursor())
        }
    }

    var currentPanelSize: PanelSize { model.panelSize }

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
        model.clearFilters()
        model.resetSelection()

        panel.setContentSize(panelSize)
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
        let size = panelSize
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
