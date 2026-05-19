import Testing
import Carbon.HIToolbox
@testable import DumbTransProCore

@MainActor
struct HotkeyManagerTests {
    @Test func start_withAllNilConfigs_registersNothing() {
        let manager = HotkeyManager()
        let result = manager.start(initial: [.rewriteToEnglish: nil, .lookup: nil])
        #expect(result.isEmpty)
        manager.stop()
    }

    @Test func reregister_withNil_unregisters_succeeds() {
        let manager = HotkeyManager()
        _ = manager.start(initial: [:])
        defer { manager.stop() }

        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey | controlKey))
        let err1 = manager.reregister(action: .rewriteToEnglish, hotkey: cfg)
        #expect(err1 == nil)

        let err2 = manager.reregister(action: .rewriteToEnglish, hotkey: nil)
        #expect(err2 == nil)
    }

    @Test func reregister_sameComboTwice_secondReturnsDuplicate() {
        let manager = HotkeyManager()
        _ = manager.start(initial: [:])
        defer { manager.stop() }

        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey | controlKey))
        let err1 = manager.reregister(action: .rewriteToEnglish, hotkey: cfg)
        let err2 = manager.reregister(action: .lookup, hotkey: cfg)
        #expect(err1 == nil)
        if case .duplicateInProcess = err2 {} else {
            Issue.record("expected duplicateInProcess, got \(String(describing: err2))")
        }
    }

    @Test func pauseAll_unregistersAllowingReregistration_resumeRestores() {
        let manager = HotkeyManager()
        _ = manager.start(initial: [:])
        defer { manager.stop() }

        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | shiftKey | controlKey))
        _ = manager.reregister(action: .rewriteToEnglish, hotkey: cfg)
        manager.pauseAll()

        // After pause, the same combo should be registrable transiently (proves we unregistered).
        let probeErr = manager.reregister(action: .lookup, hotkey: cfg)
        #expect(probeErr == nil)

        // Cleanup
        _ = manager.reregister(action: .lookup, hotkey: nil)
        manager.resumeAll()
    }
}
