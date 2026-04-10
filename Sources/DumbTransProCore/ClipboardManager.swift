import AppKit
import Carbon.HIToolbox

@MainActor
public enum ClipboardManager {
    /// Read currently selected text by simulating Cmd+C, waiting, then reading pasteboard.
    public static func getSelectedText() async -> String? {
        // Wait for user to release modifier keys from the hotkey combo
        try? await Task.sleep(for: .milliseconds(300))

        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        // Simulate Cmd+C using a fresh event source that ignores physical key state
        simulateCopy()

        // Wait for pasteboard to update (Finder can be slow)
        try? await Task.sleep(for: .milliseconds(200))

        let newText: String?
        if pasteboard.changeCount != oldChangeCount {
            newText = pasteboard.string(forType: .string)
        } else {
            newText = nil
        }

        // Restore old pasteboard contents
        if let old = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }

        return newText
    }

    /// Write text to pasteboard and simulate Cmd+V to paste.
    public static func pasteText(_ text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(for: .milliseconds(100))

        simulatePaste()
    }

    private static func simulateCopy() {
        // Use .combinedSessionState to create events independent of physical key state
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.0

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_C), keyDown: false) else {
            return
        }

        // Explicitly set ONLY Cmd flag — override any physical key state
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.0

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
