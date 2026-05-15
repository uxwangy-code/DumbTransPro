import AppKit
import Carbon.HIToolbox

private let lookupHotkeyID: UInt32 = 10

@MainActor
public final class HotkeyManager {
    public var onHotkey: (@MainActor (TranslationMode) -> Void)?
    public var onLookupHotkey: (@MainActor () -> Void)?
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

        let modifiers = UInt32(cmdKey | shiftKey)
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

        // Register ⌘⇧F for lookup
        let lookupKeyID = EventHotKeyID(signature: signature, id: lookupHotkeyID)
        var lookupRef: EventHotKeyRef?
        let lookupStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            modifiers,
            lookupKeyID,
            GetApplicationEventTarget(),
            0,
            &lookupRef
        )
        if lookupStatus == noErr, let ref = lookupRef {
            hotKeyRefs.append(ref)
            debugLog("Hotkey ⌘⇧F (lookup) registered")
        } else {
            debugLog("Failed to register ⌘⇧F (lookup): \(lookupStatus)")
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
        if let mode = TranslationMode.from(hotkeyID: id) {
            debugLog("Hotkey triggered: \(mode.rawValue) (\(mode.hotkeyLabel))")
            DispatchQueue.main.async {
                instance?.onHotkey?(mode)
            }
        } else if id == lookupHotkeyID {
            debugLog("Hotkey triggered: ⌘⇧F (lookup)")
            DispatchQueue.main.async {
                instance?.onLookupHotkey?()
            }
        } else {
            debugLog("Unknown hotkey id: \(id)")
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
    fputs("[GGS] hotKeyHandler callback fired\n", stderr)
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
    fputs("[GGS] GetEventParameter status: \(status), id: \(hotKeyID.id)\n", stderr)
    if status == noErr {
        HotkeyManager.handleHotKeyEvent(id: hotKeyID.id)
    }
    return noErr
}
