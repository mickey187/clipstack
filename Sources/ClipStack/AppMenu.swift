import AppKit

/// The main menu, installed lazily the first time a real window is shown.
///
/// ClipStack normally has no main menu at all — it is an `.accessory` app whose only
/// surface is the status item. That is fine until the activation window appears, at
/// which point it becomes a real problem: **AppKit routes ⌘X/⌘C/⌘V through the Edit
/// menu's key equivalents**, so without one the standard editing shortcuts are dead in
/// any text field.
///
/// The activation window exists purely so someone can paste a licence key into it, so
/// shipping without this menu would break the single interaction it is there to serve.
@MainActor
enum AppMenu {
    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true

        let main = NSMenu()

        // The application menu. Its title is ignored — macOS always shows the process
        // name — but the item must exist for the menu bar to be well formed.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit ClipStack",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        // The Edit menu. Every item here targets the responder chain (nil target), so
        // whatever text field is first responder handles it.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Undo", #selector(UndoActionResponder.undo(_:)), "z"),
            ("Redo", #selector(UndoActionResponder.redo(_:)), "Z"),
        ] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        edit.addItem(.separator())
        for (title, selector, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

/// `undo:` and `redo:` live on `NSUndoManager`'s responder protocol rather than on any
/// concrete AppKit class, so there is nothing to take a `#selector` from directly.
@objc private protocol UndoActionResponder {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}
