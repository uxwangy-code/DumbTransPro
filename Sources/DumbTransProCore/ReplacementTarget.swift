import AppKit
import ApplicationServices

/// A per-operation, memory-only snapshot. No text or AX identity is persisted.
@MainActor
public struct ReplacementTarget {
    let processIdentifier: Int32
    let elementIdentifier: AnyHashable
    let selectionRange: NSRange
    let selectedText: String
    let value: String?

    init(processIdentifier: Int32, elementIdentifier: AnyHashable, selectionRange: NSRange,
         selectedText: String, value: String?) {
        self.processIdentifier = processIdentifier
        self.elementIdentifier = elementIdentifier
        self.selectionRange = selectionRange
        self.selectedText = selectedText
        self.value = value
    }

    func matches(_ current: ReplacementTarget?) -> Bool {
        guard let current else { return false }
        return processIdentifier == current.processIdentifier
            && elementIdentifier == current.elementIdentifier
            && selectionRange == current.selectionRange
            && selectedText == current.selectedText
            && (value == nil || value == current.value)
    }
}

@MainActor
protocol ReplacementTargetObserving {
    func frontmostProcessIdentifier() -> Int32?
    func capture() -> ReplacementTarget?
}

private struct AXElementIdentity: Hashable {
    let element: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

@MainActor
final class AccessibilityTargetObserver: ReplacementTargetObserving {
    func frontmostProcessIdentifier() -> Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    func capture() -> ReplacementTarget? {
        guard let pid = frontmostProcessIdentifier() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        guard let focused = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        guard let selectedText = attribute(kAXSelectedTextAttribute, of: element) as? String,
              !selectedText.isEmpty,
              let selectedRange = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(selectedRange) == AXValueGetTypeID() else { return nil }
        let rangeValue = selectedRange as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0, range.length > 0,
              range.length == selectedText.utf16.count else { return nil }
        let value = attribute(kAXValueAttribute, of: element) as? String
        if let value {
            let text = value as NSString
            guard range.location <= text.length, range.length <= text.length - range.location,
                  text.substring(with: NSRange(location: range.location, length: range.length)) == selectedText else { return nil }
        }
        guard frontmostProcessIdentifier() == pid,
              let stillFocused = attribute(kAXFocusedUIElementAttribute, of: application),
              CFEqual(focused, stillFocused) else { return nil }
        return ReplacementTarget(
            processIdentifier: pid, elementIdentifier: AnyHashable(AXElementIdentity(element: element)),
            selectionRange: NSRange(location: range.location, length: range.length), selectedText: selectedText, value: value
        )
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}
