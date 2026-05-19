//
//  KS_HotKey.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

/**
A global keyboard shortcut that automatically unregisters when deallocated.

This is a low-level wrapper around Carbon's hotkey registration. For most use cases, prefer the higher-level API.

- Important: Carbon only allows one registration per unique key combination. Attempting to register the same combination twice will fail.
*/
@MainActor
final class KS_HotKey {
    let carbonKeyCode: Int
    let carbonModifiers: Int
    let onKeyDown: () -> Void
    let onKeyUp: () -> Void
    var onRegistrationFailed: (() -> Void)?

    let id: Int
    var eventHotKeyRef: EventHotKeyRef?

    enum RegisterError: Error {
        case carbonStatus(OSStatus)
    }

    /**
    Creates and registers a global keyboard shortcut.

    - Parameters:
        - carbonKeyCode: The virtual key code.
        - carbonModifiers: The modifier flags in Carbon format.
        - onKeyDown: Called when the shortcut key is pressed.
        - onKeyUp: Called when the shortcut key is released.
    - Throws: `RegisterError.carbonStatus` if Carbon registration fails (e.g., the key combination is already registered).
    */
    init(
        carbonKeyCode: Int,
        carbonModifiers: Int,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) throws {
        self.id = KS_HotKeyCenter.shared.nextId()
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        let status = KS_HotKeyCenter.shared.register(self)
        if status != noErr {
            throw RegisterError.carbonStatus(status)
        }
    }

    deinit {
        // Swift 6 guarantees @MainActor deinit runs on main actor; assumeIsolated is purely defensive.
        MainActor.assumeIsolated {
            KS_HotKeyCenter.shared.unregister(self)
        }
    }
}
#endif
