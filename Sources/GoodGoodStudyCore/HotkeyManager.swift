import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    public var onHotkey: (@MainActor () -> Void)?
    private var hotKeyRef: EventHotKeyRef?

    // Global reference for the C callback
    nonisolated(unsafe) private static var instance: HotkeyManager?

    public init() {}

    public func start() -> Bool {
        HotkeyManager.instance = self

        // Install Carbon event handler for hotkey events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        if installStatus != noErr {
            debugLog("Failed to install event handler: \(installStatus)")
            return false
        }

        // Register hotkey: F6 (no modifiers needed, simple and conflict-free)
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x47475354), // "GGST"
            id: 1
        )

        let regStatus = RegisterEventHotKey(
            UInt32(kVK_F6),
            0, // No modifiers — just F6
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            debugLog("Failed to register hotkey: \(regStatus)")
            return false
        }

        debugLog("Hotkey F6 registered successfully")
        return true
    }

    public func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        HotkeyManager.instance = nil
    }

    // Called from the C callback
    nonisolated fileprivate static func handleHotKeyEvent() {
        debugLog("Hotkey triggered!")
        DispatchQueue.main.async {
            instance?.onHotkey?()
        }
    }
}

// Debug logging to file
private func debugLog(_ message: String) {
    fputs("[GGS] \(message)\n", stderr)
}

// C-compatible callback function (no captures)
private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    HotkeyManager.handleHotKeyEvent()
    return noErr
}
