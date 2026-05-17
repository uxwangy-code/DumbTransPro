//
//  KS_ModifierFlags+Carbon.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

extension NSEvent.ModifierFlags {
    init(carbonModifiers: Int) {
        var result: NSEvent.ModifierFlags = []
        if carbonModifiers & cmdKey != 0       { result.insert(.command) }
        if carbonModifiers & optionKey != 0    { result.insert(.option) }
        if carbonModifiers & controlKey != 0   { result.insert(.control) }
        if carbonModifiers & shiftKey != 0     { result.insert(.shift) }
        self = result
    }

    /// Subset of these flags that map to Carbon modifier bits. Strips device-independent
    /// bits we don't care about (capsLock, numericPad, etc.).
    var carbonRepresentation: Int {
        var result = 0
        if contains(.command) { result |= cmdKey }
        if contains(.option)  { result |= optionKey }
        if contains(.control) { result |= controlKey }
        if contains(.shift)   { result |= shiftKey }
        return result
    }
}
#endif
