import Testing
import Carbon.HIToolbox
@testable import DumbTransProCore

struct HotkeyConfigTests {
    @Test func displayString_letterA_cmd() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey))
        #expect(cfg.displayString == "⌘A")
    }

    @Test func displayString_letterR_cmdShift() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
        #expect(cfg.displayString == "⇧⌘R")
    }

    @Test func displayString_modifierOrder_ctrlOptShiftCmd() {
        let cfg = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        #expect(cfg.displayString == "⌃⌥⇧⌘F")
    }

    @Test func displayString_space() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        #expect(cfg.displayString == "⌘Space")
    }

    @Test func displayString_functionKey_F1() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_F1), modifiers: UInt32(controlKey))
        #expect(cfg.displayString == "⌃F1")
    }

    @Test func displayString_arrow() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey))
        #expect(cfg.displayString == "⌘←")
    }

    @Test func displayString_unknown_fallback() {
        let cfg = HotkeyConfig(keyCode: 9999, modifiers: UInt32(cmdKey))
        #expect(cfg.displayString.hasPrefix("⌘?"))
    }

    @Test func codable_roundTrip() throws {
        let original = HotkeyConfig(keyCode: 15, modifiers: 1024)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func defaultHotkey_rewriteToEnglish_isCmdShiftR() {
        let cfg = TranslationAction.rewriteToEnglish.defaultHotkey
        #expect(cfg.keyCode == UInt32(kVK_ANSI_R))
        #expect(cfg.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func defaultHotkey_lookup_isCmdShiftF() {
        let cfg = TranslationAction.lookup.defaultHotkey
        #expect(cfg.keyCode == UInt32(kVK_ANSI_F))
        #expect(cfg.modifiers == UInt32(cmdKey | shiftKey))
    }
}
