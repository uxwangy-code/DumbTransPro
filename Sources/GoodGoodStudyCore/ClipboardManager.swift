import AppKit
import Carbon.HIToolbox

@MainActor
public enum ClipboardManager {
    /// Read currently selected text by simulating Cmd+C, waiting, then reading pasteboard.
    public static func getSelectedText() async -> String? {
        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        // Simulate Cmd+C
        simulateKeyPress(keyCode: UInt16(kVK_ANSI_C), flags: .maskCommand)

        // Wait for pasteboard to update
        try? await Task.sleep(for: .milliseconds(100))

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
        try? await Task.sleep(for: .milliseconds(50))

        simulateKeyPress(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
    }

    private static func simulateKeyPress(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
