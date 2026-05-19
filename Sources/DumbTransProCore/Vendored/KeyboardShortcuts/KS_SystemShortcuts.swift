//
//  KS_SystemShortcuts.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

enum KS_SystemShortcuts {
    /// Returns all currently-enabled system-defined keyboard shortcuts via Carbon `CopySymbolicHotKeys`.
    static var all: [(carbonKeyCode: Int, carbonModifiers: Int)] {
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
            let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
        else {
            return []
        }
        return shortcuts.compactMap {
            guard
                ($0[kHISymbolicHotKeyEnabled] as? Bool) == true,
                let carbonKeyCode = $0[kHISymbolicHotKeyCode] as? Int,
                let carbonModifiers = $0[kHISymbolicHotKeyModifiers] as? Int
            else { return nil }
            return (carbonKeyCode, carbonModifiers)
        }
    }

    /// True if the given Carbon combo is registered in macOS as a symbolic hotkey.
    /// F12 is excluded (system reports it but it's unused on modern macOS).
    /// - Note: Calls CopySymbolicHotKeys (IPC) on every invocation. Cache the result if calling frequently (e.g., per recording session).
    static func contains(carbonKeyCode: Int, carbonModifiers: Int) -> Bool {
        if carbonKeyCode == kVK_F12, carbonModifiers == 0 { return false }
        let normalized = NSEvent.ModifierFlags(carbonModifiers: carbonModifiers).carbonRepresentation
        return all.contains { entry in
            entry.carbonKeyCode == carbonKeyCode
                && NSEvent.ModifierFlags(carbonModifiers: entry.carbonModifiers).carbonRepresentation == normalized
        }
    }
}
#endif
