import Testing
import Foundation
import Carbon.HIToolbox
@testable import DumbTransProCore

@MainActor
private final class FakeHotkeyBackend: HotkeyRegistrationBackend {
    var registrations: [HotkeyConfig] = []
    var callbacks: [@MainActor () -> Void] = []
    var error: OSStatus?
    func register(config: HotkeyConfig, onKeyDown: @escaping @MainActor () -> Void) throws -> AnyObject {
        if let error { throw KS_HotKey.RegisterError.carbonStatus(error) }
        registrations.append(config)
        callbacks.append(onKeyDown)
        return NSObject()
    }
    func pauseAll() {}
    func resumeAll() {}
}

@MainActor
struct HotkeyManagerTests {
    @Test func explicitDisabledActionsNeverReachRegistration() {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)
        #expect(manager.start(initial: [.rewriteToEnglish: nil, .lookup: nil]).isEmpty)
        #expect(backend.registrations.isEmpty)
    }

    @Test func invalidModifiersAreRejectedBeforeRegistration() {
        for modifiers in [UInt32(0), UInt32(shiftKey), UInt32(alphaLock), UInt32(shiftKey | alphaLock)] {
            let backend = FakeHotkeyBackend()
            let manager = HotkeyManager(backend: backend)
            let config = HotkeyConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: modifiers)
            #expect(manager.reregister(action: .lookup, hotkey: config) == .invalidParameter)
            #expect(backend.registrations.isEmpty)
        }
    }

    @Test func validShortcutRoutesTheRequestedAction() async throws {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)
        var actions: [TranslationAction] = []
        manager.onAction = { actions.append($0) }
        let config = HotkeyConfig(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey))
        #expect(manager.reregister(action: .lookup, hotkey: config) == nil)
        #expect(backend.registrations == [config])
        try #require(backend.callbacks.count == 1)
        backend.callbacks[0]()
        // Hotkey callbacks are dispatched as main-actor tasks by the manager.
        for _ in 0..<10 where actions.isEmpty { await Task.yield() }
        #expect(actions == [.lookup])
    }

    @Test func carbonRegistrationFailuresAreMappedForTheCaller() {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)
        for (status, expected) in [(OSStatus(eventHotKeyExistsErr), HotkeyManager.RegisterError.duplicateInProcess),
                                   (OSStatus(paramErr), .invalidParameter), (OSStatus(-12345), .unknown(-12345))] {
            backend.error = status
            #expect(manager.reregister(action: .lookup, hotkey: TranslationAction.lookup.defaultHotkey) == expected)
        }
    }
}
