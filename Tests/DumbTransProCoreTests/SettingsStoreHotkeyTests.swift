import Testing
import Carbon.HIToolbox
import Foundation
@testable import DumbTransProCore

@MainActor
struct SettingsStoreHotkeyTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.hotkey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func hotkey_unsetKey_returnsDefault() {
        let store = SettingsStore(defaults: freshDefaults())
        let cfg = store.hotkey(for: .rewriteToEnglish)
        #expect(cfg == TranslationAction.rewriteToEnglish.defaultHotkey)
    }

    @Test func setHotkey_persistsAndReturns() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        let custom = HotkeyConfig(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey))
        store.setHotkey(custom, for: .rewriteToEnglish)
        #expect(store.hotkey(for: .rewriteToEnglish) == custom)

        // Persistence check: a fresh store on the same defaults should see the value.
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hotkey(for: .rewriteToEnglish) == custom)
    }

    @Test func setHotkey_nil_returnsExplicitNil_notDefault() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.setHotkey(nil, for: .lookup)
        #expect(store.hotkey(for: .lookup) == nil)

        // Survives reload.
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hotkey(for: .lookup) == nil)
    }

    @Test func resetHotkey_returnsToDefault() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        let custom = HotkeyConfig(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))
        store.setHotkey(custom, for: .lookup)
        store.resetHotkey(for: .lookup)
        #expect(store.hotkey(for: .lookup) == TranslationAction.lookup.defaultHotkey)
        #expect(defaults.object(forKey: "hotkey.lookup") == nil)

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hotkey(for: .lookup) == TranslationAction.lookup.defaultHotkey)
    }

    @Test func hotkeys_publishedMapReflectsAllActions() {
        let store = SettingsStore(defaults: freshDefaults())
        #expect(store.hotkey(for: .rewriteToEnglish) == TranslationAction.rewriteToEnglish.defaultHotkey)
        #expect(store.hotkey(for: .lookup) == TranslationAction.lookup.defaultHotkey)
        #expect(store.hotkeys.keys.count == TranslationAction.allCases.count)
    }
}
