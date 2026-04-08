import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    public var onHotkey: (@MainActor () -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Store a global reference for the C callback
    private static var instance: HotkeyManager?

    public init() {}

    public func start() -> Bool {
        HotkeyManager.instance = self

        // Register event handler for hot key events
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let manager = HotkeyManager.instance else { return OSStatus(eventNotHandledErr) }
                manager.onHotkey?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else { return false }

        // Register the hot key: Option+Cmd+K
        // kVK_ANSI_K = 0x28 = 40
        let hotKeyID = EventHotKeyID(signature: OSType(0x47475354), // "GGST"
                                      id: 1)
        let modifiers: UInt32 = UInt32(optionKey | cmdKey)

        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        return regStatus == noErr
    }

    public func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        HotkeyManager.instance = nil
    }
}
