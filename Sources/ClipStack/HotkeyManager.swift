import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via HIToolbox.
///
/// `RegisterEventHotKey` needs no Accessibility grant — unlike the synthetic paste —
/// so the popup opens even before the user has granted anything.
@MainActor
final class HotkeyManager {
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
    }

    static let keyV = UInt32(kVK_ANSI_V)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Carbon dispatches to a C callback with no context, so the live instance is
    /// parked here. There is exactly one HotkeyManager for the app's lifetime.
    private static weak var active: HotkeyManager?

    @discardableResult
    func register(keyCode: UInt32, modifiers: Modifiers, handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler
        Self.active = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr, hotKeyID.signature == HotkeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotkeyManager.active?.handler?() }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        guard status == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        return registerStatus == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
    }

    /// 'CLSK' — identifies our hot key in the shared Carbon event stream.
    private static let signature: OSType = 0x434C_534B
}
