import Testing
import Carbon.HIToolbox
@testable import DumbTransProCore

struct HotkeyChipReducerTests {
    private let sampleCfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))

    @Test func chipClicked_fromResting_entersRecording_emitsInstallMonitorAndPause() {
        let (newState, effects) = HotkeyChipReducer.reduce(state: .resting, event: .chipClicked)
        #expect(newState == .recording(returnTo: .resting))
        #expect(effects.contains(.installMonitor))
        #expect(effects.contains(.pauseAllHotkeys))
    }

    @Test func chipClicked_fromCleared_entersRecording_withReturnToCleared() {
        let (newState, _) = HotkeyChipReducer.reduce(state: .cleared, event: .chipClicked)
        #expect(newState == .recording(returnTo: .cleared))
    }

    @Test func clearClicked_fromResting_goesToClearedAndCommitsNil() {
        let (newState, effects) = HotkeyChipReducer.reduce(state: .resting, event: .clearClicked)
        #expect(newState == .cleared)
        #expect(effects.contains(.commit(nil)))
    }

    @Test func esc_inRecording_returnsToReturnToState_andResumes() {
        let state: RecorderState = .recording(returnTo: .resting)
        let (newState, effects) = HotkeyChipReducer.reduce(state: state, event: .escPressed)
        #expect(newState == .resting)
        #expect(effects.contains(.removeMonitor))
        #expect(effects.contains(.resumeAllHotkeys))
        let hasCommit = effects.contains(where: { if case .commit = $0 { return true } else { return false } })
        #expect(!hasCommit)
    }

    @Test func delete_inRecording_goesToCleared() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .deleteOrBackspacePressed
        )
        #expect(newState == .cleared)
        #expect(effects.contains(.commit(nil)))
    }

    @Test func tab_inRecording_returnsToReturnToStateAndMovesFocus() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .tabPressed
        )
        #expect(newState == .resting)
        #expect(effects.contains(.moveFocusToNextResponder))
    }

    @Test func validKeyDown_noConflict_commitsAndReturnsToResting() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .keyDown(config: sampleCfg, conflict: .none)
        )
        #expect(newState == .resting)
        #expect(effects.contains(.commit(sampleCfg)))
        #expect(effects.contains(.resumeAllHotkeys))
    }

    @Test func validKeyDown_appInternalConflict_goesToConflict_noCommit() {
        let state: RecorderState = .recording(returnTo: .resting)
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: state,
            event: .keyDown(config: sampleCfg, conflict: .appInternal(otherActionTitle: "划词翻译"))
        )
        if case .conflict(let label, let returnTo) = newState {
            #expect(label.contains("划词翻译"))
            #expect(returnTo == .resting)
        } else {
            Issue.record("expected .conflict state, got \(newState)")
        }
        let hasCommit = effects.contains(where: { if case .commit = $0 { return true } else { return false } })
        #expect(!hasCommit)
    }

    @Test func validKeyDown_systemConflict_savesAsWarning() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .keyDown(config: sampleCfg, conflict: .system)
        )
        if case .warning = newState {} else {
            Issue.record("expected .warning state, got \(newState)")
        }
        #expect(effects.contains(.commit(sampleCfg)))
    }

    @Test func validKeyDown_mainMenuConflict_savesAsWarning() {
        let (newState, _) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .keyDown(config: sampleCfg, conflict: .mainMenu(itemTitle: "退出"))
        )
        if case .warning(let label) = newState {
            #expect(label.contains("退出"))
        } else {
            Issue.record("expected .warning, got \(newState)")
        }
    }

    @Test func invalidKeyDown_keepsRecording_emitsBeep() {
        let state: RecorderState = .recording(returnTo: .resting)
        let (newState, effects) = HotkeyChipReducer.reduce(state: state, event: .invalidKeyDown)
        #expect(newState == state)
        #expect(effects.contains(.beep))
    }

    @Test func resetClicked_inRecording_commitsDefaultAndReturnsToResting() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .resetClicked
        )
        #expect(newState == .resting)
        #expect(effects.contains(.commitDefault))
    }

    @Test func focusLost_inRecording_returnsToReturnToState() {
        let (newState, _) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .cleared),
            event: .focusLost
        )
        #expect(newState == .cleared)
    }

    @Test func esc_fromConflict_returnsToReturnToState() {
        let (newState, _) = HotkeyChipReducer.reduce(
            state: .conflict(label: "X", returnTo: .resting),
            event: .escPressed
        )
        #expect(newState == .resting)
    }
}
