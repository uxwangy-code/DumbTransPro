//
//  KS_MainMenu.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

@MainActor
enum KS_MainMenu {
    /// Recursively searches `NSApp.mainMenu` for a menu item whose `keyEquivalent` matches
    /// the given Carbon keyCode + modifiers. Returns the item if found.
    static func itemMatching(carbonKeyCode: Int, carbonModifiers: Int) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        let modifiers = NSEvent.ModifierFlags(carbonModifiers: carbonModifiers)
        let expectedKeyEquivalent = keyEquivalent(forCarbonKeyCode: carbonKeyCode, modifiers: modifiers)
        return search(in: mainMenu, keyEquivalent: expectedKeyEquivalent, modifiers: modifiers)
    }

    private static func search(
        in menu: NSMenu,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem? {
        for item in menu.items {
            var itemKeyEquivalent = item.keyEquivalent
            var itemModifierMask = item.keyEquivalentModifierMask
            if modifiers.contains(.shift), itemKeyEquivalent.lowercased() != itemKeyEquivalent {
                itemKeyEquivalent = itemKeyEquivalent.lowercased()
                itemModifierMask.insert(.shift)
            }
            if !itemKeyEquivalent.isEmpty,
               itemKeyEquivalent == keyEquivalent,
               modifiers == itemModifierMask {
                return item
            }
            if let submenu = item.submenu,
               let match = search(in: submenu, keyEquivalent: keyEquivalent, modifiers: modifiers) {
                return match
            }
        }
        return nil
    }

    private static func keyEquivalent(forCarbonKeyCode keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        // For ASCII letter/digit keyCodes, derive lowercase char (mainMenu key equivalents are typically lowercase
        // with shift represented as a modifier flag). For special keys, return the character literal AppKit uses.
        return KS_KeyCodeToChar.lowercaseChar(forCarbonKeyCode: keyCode)
    }
}

/// Minimal keyCode → lowercase character mapping for NSMenuItem.keyEquivalent comparison.
enum KS_KeyCodeToChar {
    static func lowercaseChar(forCarbonKeyCode keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Return:  return "\r"
        case kVK_Tab:     return "\t"
        case kVK_Space:   return " "
        case kVK_Delete:  return "\u{8}"
        case kVK_Escape:  return "\u{1B}"
        default:          return ""
        }
    }
}
#endif
