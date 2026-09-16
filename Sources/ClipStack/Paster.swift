import AppKit
import Carbon.HIToolbox
import ClipStackCore

/// Writes an item back to the pasteboard and pastes it into the app the user was
/// last in (PRD F6).
///
/// The hard part is focus, not the keystroke: our panel takes key focus while it is
/// open, so we must return the previously frontmost app to the front and *wait until
/// it actually is* before synthesising ⌘V. Posting too early is the classic failure
/// here — the keystroke lands in the void — which is why this polls rather than
/// sleeping for a guessed interval.
@MainActor
enum Paster {
    /// Stamped on anything we put on the pasteboard so `ClipboardMonitor` can tell
    /// our own writes apart from a genuine user copy.
    static let internalType = NSPasteboard.PasteboardType("com.clipstack.internal")

    enum Result {
        /// Written to the pasteboard and ⌘V delivered.
        case pasted
        /// Written to the pasteboard only — no Accessibility grant, so the user
        /// has to press ⌘V themselves.
        case copiedOnly
    }

    /// Puts the item on the general pasteboard, marked as ours.
    static func writeToPasteboard(_ item: ClipboardItem, store: ClipboardStore) {
        let pasteboard = NSPasteboard.general
        switch item.type {
        case .text:
            pasteboard.declareTypes([.string, internalType], owner: nil)
            pasteboard.setString(item.textValue ?? "", forType: .string)
        case .image:
            guard let data = store.imageData(for: item) else { return }
            pasteboard.declareTypes([.png, internalType], owner: nil)
            pasteboard.setData(data, forType: .png)
        }
        pasteboard.setData(Data(), forType: internalType)
    }

    /// Restores `target` to the front, then pastes.
    static func paste(
        _ item: ClipboardItem,
        store: ClipboardStore,
        into target: NSRunningApplication?
    ) async -> Result {
        writeToPasteboard(item, store: store)

        let targetName = target?.localizedName ?? "none"
        guard Permissions.hasAccessibility else {
            pasteLog.notice("copied only: AXIsProcessTrusted() == false (target: \(targetName, privacy: .public))")
            return .copiedOnly
        }

        if let target, !target.isActive {
            target.activate()
            // Wait for the switch to actually land — up to ~300ms.
            var restored = false
            for _ in 0..<30 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == target.processIdentifier {
                    restored = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            if !restored {
                let actual = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
                pasteLog.error("focus not restored to \(targetName, privacy: .public); frontmost is \(actual, privacy: .public)")
            }
            // Activation completing is not the same as the key window being ready
            // to receive events; give it one more beat.
            try? await Task.sleep(for: .milliseconds(30))
        } else if target == nil {
            pasteLog.error("no target app recorded; pasting into whatever is frontmost")
        }

        postCommandV()
        pasteLog.notice("posted ⌘V to \(targetName, privacy: .public)")
        return .pasted
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Keep any physically-held modifiers from bleeding into our synthetic event.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
