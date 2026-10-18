import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
private final class FakePasteboard: ClipboardAccess {
    var changeCount = 0
    var items: ClipboardSnapshot = []
    var afterWrite: (() -> Void)?
    var string: String? { items.first?["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) } }
    func snapshot() -> ClipboardSnapshot { items }
    func replace(with snapshot: ClipboardSnapshot) {
        items = snapshot
        changeCount += 1
        afterWrite?()
    }
    func writeText(_ text: String) { replace(with: [["public.utf8-plain-text": Data(text.utf8)]]) }
}

@MainActor
private final class FakeTargetObserver: ReplacementTargetObserving {
    var pid: Int32? = 1
    var target: ReplacementTarget? = ReplacementTarget(
        processIdentifier: 1, elementIdentifier: "field", selectionRange: NSRange(location: 0, length: 5),
        selectedText: "hello", value: "hello world"
    )
    func frontmostProcessIdentifier() -> Int32? { pid }
    func capture() -> ReplacementTarget? { target }
}

@MainActor
private final class FakeClipboardEvents: ClipboardEventSending {
    var copy: () -> Bool = { true }
    var paste: () -> Bool = { true }
    func requestCopy() -> Bool { copy() }
    func requestPaste() -> Bool { paste() }
}

@MainActor
struct ClipboardManagerTests {
    @Test func copyRestoresAllTypesIncludingEmptyClipboard() async throws {
        let snapshots: [ClipboardSnapshot] = [[], [["public.png": Data([1, 2]), "public.file-url": Data("file:///tmp/a".utf8)]]]
        for original in snapshots {
            let board = FakePasteboard()
            board.items = original
            let observer = FakeTargetObserver()
            let events = FakeClipboardEvents()
            events.copy = { board.writeText("hello"); return true }
            let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in })
            let result = try await manager.captureSelection()
            #expect(result?.text == "hello")
            #expect(result?.target != nil)
            #expect(board.items == original)
        }
    }

    @Test func focusChangeDuringInitialWaitPreventsCopy() async {
        let board = FakePasteboard()
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        var copies = 0
        events.copy = { copies += 1; return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in observer.pid = 2 })
        await #expect(throws: ClipboardOperationError.targetChanged) { try await manager.captureSelection() }
        #expect(copies == 0)
        #expect(board.changeCount == 0)
    }

    @Test func copyOfDifferentTextDoesNotOverwriteUserClipboard() async {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        events.copy = { board.writeText("user copied something else"); return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in })
        await #expect(throws: ClipboardOperationError.clipboardChanged) { try await manager.captureSelection() }
        #expect(board.string == "user copied something else")
    }

    @Test func sharedBusyGateRejectsBothCopyAndPasteDuringCapture() async throws {
        let board = FakePasteboard()
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        events.copy = { board.writeText("hello"); return true }
        var manager: ClipboardCoordinator!
        var checked = false
        manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in
            guard !checked else { return }
            checked = true
            await #expect(throws: ClipboardOperationError.busy) { try await manager.captureSelection() }
            await #expect(throws: ClipboardOperationError.busy) { try await manager.pasteText("你好", replacing: observer.target) }
        })
        _ = try await manager.captureSelection()
        #expect(checked)
        #expect(!manager.isBusy)
    }

    @Test func unsupportedTargetCanBeCopiedButCannotBePasted() async throws {
        let board = FakePasteboard()
        let observer = FakeTargetObserver()
        observer.target = nil
        let events = FakeClipboardEvents()
        events.copy = { board.writeText("hello"); return true }
        var pastes = 0
        events.paste = { pastes += 1; return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in })
        let selection = try await manager.captureSelection()
        #expect(selection?.text == "hello")
        #expect(selection?.target == nil)
        let result = try await manager.pasteText("你好", replacing: selection?.target)
        #expect(result == .targetChanged)
        #expect(pastes == 0)
        #expect(board.string == "hello")
    }

    @Test func finalTargetCheckAfterPreparingClipboardPreventsPaste() async throws {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let original = observer.target
        let events = FakeClipboardEvents()
        var pastes = 0
        events.paste = { pastes += 1; return true }
        board.afterWrite = { observer.target = nil }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in })
        let result = try await manager.pasteText("你好", replacing: original)
        #expect(result == .targetChanged)
        #expect(pastes == 0)
        #expect(board.string == "previous")
    }

    @Test func pasteRestoresPreviousClipboardUnlessUserCopiedAgain() async throws {
        for userCopiesAgain in [false, true] {
            let board = FakePasteboard()
            board.items = [["public.png": Data([1, 2, 3])]]
            let original = board.items
            let observer = FakeTargetObserver()
            let events = FakeClipboardEvents()
            var pasted: String?
            events.paste = { pasted = board.string; return true }
            let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in
                if userCopiesAgain, pasted != nil { board.writeText("user copied") }
            })
            let result = try await manager.pasteText("你好", replacing: observer.target)
            #expect(result == .pasteRequested)
            #expect(pasted == "你好")
            if userCopiesAgain { #expect(board.string == "user copied") }
            else { #expect(board.items == original) }
            #expect(!manager.isBusy)
        }
    }

    @Test func pasteLetsReceiverObserveNewClipboardBeforeSendingKey() async throws {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        var receiverHasObservedChange = false
        var received: String?
        var sent = false
        events.paste = {
            sent = true
            // Chromium can discard a paste if its delayed clipboard-change
            // notification arrives during the command (crbug.com/568453825).
            if receiverHasObservedChange { received = board.string }
            return true
        }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in
            if !sent, board.string == "你好" { receiverHasObservedChange = true }
        })
        let result = try await manager.pasteText("你好", replacing: observer.target)
        #expect(result == .pasteRequested)
        #expect(received == "你好")
        #expect(board.string == "previous")
    }

    @Test func focusChangeWhileClipboardSettlesPreventsPaste() async throws {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let originalTarget = observer.target
        let events = FakeClipboardEvents()
        var pastes = 0
        events.paste = { pastes += 1; return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in
            observer.pid = 2
        })
        let result = try await manager.pasteText("你好", replacing: originalTarget)
        #expect(result == .targetChanged)
        #expect(pastes == 0)
        #expect(board.string == "previous")
    }

    @Test func userCopyWhileClipboardSettlesPreventsPasteAndKeepsNewCopy() async {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        var pastes = 0
        events.paste = { pastes += 1; return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in
            board.writeText("user copied")
        })
        await #expect(throws: ClipboardOperationError.clipboardChanged) {
            try await manager.pasteText("你好", replacing: observer.target)
        }
        #expect(pastes == 0)
        #expect(board.string == "user copied")
        #expect(!manager.isBusy)
    }

    @Test func cancellationWhileClipboardSettlesRestoresClipboardWithoutPasting() async {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        var pastes = 0
        events.paste = { pastes += 1; return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) {
            try await manager.pasteText("你好", replacing: observer.target)
        }
        #expect(pastes == 0)
        #expect(board.string == "previous")
        #expect(!manager.isBusy)
    }

    @Test func cancelledCopyRestoresOwnedClipboardAndReleasesGate() async {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        events.copy = { board.writeText("hello"); return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { duration in
            if duration == 25 { throw CancellationError() }
        })
        await #expect(throws: CancellationError.self) { try await manager.captureSelection() }
        #expect(board.string == "previous")
        #expect(!manager.isBusy)
    }

    @Test func targetChangeAfterCopyReturnsNoTextAndRestoresClipboard() async {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        let events = FakeClipboardEvents()
        events.copy = { board.writeText("hello"); return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { duration in
            if duration == 25 { observer.target = nil }
        })
        await #expect(throws: ClipboardOperationError.targetChanged) { try await manager.captureSelection() }
        #expect(board.string == "previous")
    }

    @Test func unsupportedAXDoesNotRestoreOverAnUnverifiableNewCopy() async throws {
        let board = FakePasteboard()
        board.writeText("previous")
        let observer = FakeTargetObserver()
        observer.target = nil
        let events = FakeClipboardEvents()
        events.copy = { board.writeText("user copied something else"); return true }
        let manager = ClipboardCoordinator(pasteboard: board, targets: observer, events: events, wait: { _ in })
        let selection = try await manager.captureSelection()
        #expect(selection?.target == nil)
        #expect(board.string == "user copied something else")
    }
}
