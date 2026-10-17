import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
struct ReplacementTargetTests {
    @Test func anyFocusSelectionOrContentChangeBlocksReplacement() {
        let original = target()
        #expect(original.matches(target()))
        #expect(!original.matches(target(pid: 2)))
        #expect(!original.matches(target(element: "another-field")))
        #expect(!original.matches(target(range: NSRange(location: 1, length: 5))))
        #expect(!original.matches(target(text: "other")))
        #expect(!original.matches(target(value: "hello changed")))
        #expect(!original.matches(target(value: nil)))
        #expect(!original.matches(nil))
    }

    @Test func unreadableValueStillRequiresSameElementRangeAndText() {
        let original = target(value: nil)
        #expect(original.matches(target(value: nil)))
        #expect(!original.matches(target(text: "other", value: nil)))
    }

    private func target(
        pid: Int32 = 1, element: String = "field", range: NSRange = NSRange(location: 0, length: 5),
        text: String = "hello", value: String? = "hello world"
    ) -> ReplacementTarget {
        ReplacementTarget(processIdentifier: pid, elementIdentifier: element,
                          selectionRange: range, selectedText: text, value: value)
    }
}
