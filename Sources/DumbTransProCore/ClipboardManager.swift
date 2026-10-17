import AppKit
import Carbon.HIToolbox

public enum ClipboardOperationError: Error, Equatable, LocalizedError {
    case busy
    case targetChanged
    case clipboardChanged
    case eventUnavailable

    public var errorDescription: String? {
        switch self {
        case .busy: return "正在读取或恢复剪贴板，请稍后重试"
        case .targetChanged: return "选中的位置已改变，请重新选中文字后重试"
        case .clipboardChanged: return "剪贴板内容已改变，请重新选中文字后重试"
        case .eventUnavailable: return "无法发送复制或粘贴按键，请检查辅助功能权限"
        }
    }
}

public enum PasteOutcome: Equatable, Sendable {
    /// The key event was sent; the receiving app does not acknowledge replacement success.
    case pasteRequested
    case targetChanged
}

@MainActor
public struct ClipboardSelection {
    public let text: String
    public let target: ReplacementTarget?
}

@MainActor
public enum ClipboardManager {
    private static let coordinator = ClipboardCoordinator(
        pasteboard: SystemClipboard(), targets: AccessibilityTargetObserver(), events: SystemClipboardEvents()
    )

    public static func captureSelection() async throws -> ClipboardSelection? {
        try await coordinator.captureSelection()
    }

    public static func getSelectedText() async -> String? {
        try? await captureSelection()?.text
    }

    public static func pasteText(_ text: String, replacing target: ReplacementTarget?) async throws -> PasteOutcome {
        try await coordinator.pasteText(text, replacing: target)
    }
}

typealias ClipboardSnapshot = [[String: Data]]

@MainActor
protocol ClipboardAccess {
    var changeCount: Int { get }
    var string: String? { get }
    func snapshot() -> ClipboardSnapshot
    func replace(with snapshot: ClipboardSnapshot)
    func writeText(_ text: String)
}

@MainActor
protocol ClipboardEventSending {
    func requestCopy() -> Bool
    func requestPaste() -> Bool
}

@MainActor
final class ClipboardCoordinator {
    private let pasteboard: any ClipboardAccess
    private let targets: any ReplacementTargetObserving
    private let events: any ClipboardEventSending
    private let wait: @MainActor (Int) async throws -> Void
    private(set) var isBusy = false

    init(pasteboard: any ClipboardAccess, targets: any ReplacementTargetObserving,
         events: any ClipboardEventSending,
         wait: @escaping @MainActor (Int) async throws -> Void = { milliseconds in
             // Once a key event is posted, cancellation must not shorten the receiver's read window.
             try await Task { @MainActor in
                 try await Task.sleep(for: .milliseconds(milliseconds))
             }.value
         }) {
        self.pasteboard = pasteboard
        self.targets = targets
        self.events = events
        self.wait = wait
    }

    func captureSelection() async throws -> ClipboardSelection? {
        guard !isBusy else { throw ClipboardOperationError.busy }
        isBusy = true
        defer { isBusy = false }

        // Capture before the first suspension, while the hotkey's app is still focused.
        let pid = targets.frontmostProcessIdentifier()
        let target = targets.capture()
        try await wait(120)
        try Task.checkCancellation()
        guard sameCaptureTarget(pid: pid, target: target) else { throw ClipboardOperationError.targetChanged }

        let initialCount = pasteboard.changeCount
        let original = pasteboard.snapshot()
        guard pasteboard.changeCount == initialCount else { throw ClipboardOperationError.clipboardChanged }
        guard events.requestCopy() else { throw ClipboardOperationError.eventUnavailable }

        var ownedCount: Int?
        defer {
            if let ownedCount, pasteboard.changeCount == ownedCount { pasteboard.replace(with: original) }
        }
        // Do not retry Cmd+C after a suspension: a stale request could hit a new field.
        for _ in 0..<24 {
            do { try await wait(25) }
            catch {
                if let target, pasteboard.changeCount != initialCount, pasteboard.string == target.selectedText {
                    ownedCount = pasteboard.changeCount
                }
                throw error
            }
            if pasteboard.changeCount != initialCount {
                let count = pasteboard.changeCount
                let text = pasteboard.string
                // A different string cannot belong to the selection we copied. Leave it untouched.
                if let target, text != target.selectedText { throw ClipboardOperationError.clipboardChanged }
                // Without an AX text snapshot, a new value might be the user's own copy.
                // We can show it as a manual result, but cannot safely restore over it.
                if target != nil { ownedCount = count }
                try Task.checkCancellation()
                guard sameCaptureTarget(pid: pid, target: target) else { throw ClipboardOperationError.targetChanged }
                guard pasteboard.changeCount == count else { throw ClipboardOperationError.clipboardChanged }
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return ClipboardSelection(text: text, target: target)
            }
            try Task.checkCancellation()
            guard sameCaptureTarget(pid: pid, target: target) else { throw ClipboardOperationError.targetChanged }
        }
        return nil
    }

    func pasteText(_ text: String, replacing target: ReplacementTarget?) async throws -> PasteOutcome {
        guard !isBusy else { throw ClipboardOperationError.busy }
        isBusy = true
        defer { isBusy = false }
        try Task.checkCancellation()
        let output = try TranslationOutputValidator.validate(text)
        guard let target, target.matches(targets.capture()),
              targets.frontmostProcessIdentifier() == target.processIdentifier else { return .targetChanged }

        let originalCount = pasteboard.changeCount
        let original = pasteboard.snapshot()
        guard pasteboard.changeCount == originalCount else { throw ClipboardOperationError.clipboardChanged }
        pasteboard.writeText(output)
        let ownedCount = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == ownedCount { pasteboard.replace(with: original) }
        }

        // No actor suspension occurs between the last check and Cmd+V.
        guard target.matches(targets.capture()),
              targets.frontmostProcessIdentifier() == target.processIdentifier else { return .targetChanged }
        guard pasteboard.changeCount == ownedCount else { throw ClipboardOperationError.clipboardChanged }
        guard events.requestPaste() else { throw ClipboardOperationError.eventUnavailable }
        // Allow the receiving app to consume Cmd+V before restoring our temporary clipboard.
        try? await wait(250)
        return .pasteRequested
    }

    private func sameCaptureTarget(pid: Int32?, target: ReplacementTarget?) -> Bool {
        guard let pid, targets.frontmostProcessIdentifier() == pid else { return false }
        return target.map { $0.matches(targets.capture()) } ?? true
    }
}

@MainActor
private final class SystemClipboard: ClipboardAccess {
    private var pasteboard: NSPasteboard { .general }
    var changeCount: Int { pasteboard.changeCount }
    var string: String? { pasteboard.string(forType: .string) }
    func snapshot() -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type.rawValue, $0) }
            })
        }
    }
    func replace(with snapshot: ClipboardSnapshot) {
        let items = snapshot.map { data in
            let item = NSPasteboardItem()
            for (type, value) in data { item.setData(value, forType: .init(type)) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
    func writeText(_ text: String) {
        replace(with: [[NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)]])
    }
}

@MainActor
private final class SystemClipboardEvents: ClipboardEventSending {
    func requestCopy() -> Bool { send(key: UInt16(kVK_ANSI_C)) }
    func requestPaste() -> Bool { send(key: UInt16(kVK_ANSI_V)) }
    private func send(key: UInt16) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
