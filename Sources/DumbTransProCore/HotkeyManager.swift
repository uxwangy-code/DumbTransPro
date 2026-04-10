import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    public var onHotkey: (@MainActor (TranslationMode) -> Void)?
    private var hotKeyRefs: [EventHotKeyRef] = []

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

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let signature = OSType(0x44545052) // "DTPR"

        for mode in TranslationMode.allCases {
            let hotKeyID = EventHotKeyID(signature: signature, id: mode.hotkeyID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                mode.keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status != noErr {
                debugLog("Failed to register hotkey \(mode.hotkeyLabel): \(status)")
                continue
            }
            if let ref = ref {
                hotKeyRefs.append(ref)
            }
            debugLog("Hotkey \(mode.hotkeyLabel) (\(mode.rawValue)) registered")
        }

        return !hotKeyRefs.isEmpty
    }

    public func stop() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        HotkeyManager.instance = nil
    }

    // Called from the C callback
    nonisolated fileprivate static func handleHotKeyEvent(id: UInt32) {
        guard let mode = TranslationMode.from(hotkeyID: id) else {
            debugLog("Unknown hotkey id: \(id)")
            return
        }
        debugLog("Hotkey triggered: \(mode.rawValue) (\(mode.hotkeyLabel))")
        DispatchQueue.main.async {
            instance?.onHotkey?(mode)
        }
    }
}

// Debug logging to stderr
private func debugLog(_ message: String) {
    fputs("[GGS] \(message)\n", stderr)
}

// C-compatible callback function
private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr {
        HotkeyManager.handleHotKeyEvent(id: hotKeyID.id)
    }
    return noErr
}
