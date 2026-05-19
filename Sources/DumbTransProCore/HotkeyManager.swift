import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    public var onAction: (@MainActor (TranslationAction) -> Void)?

    public enum RegisterError: Error, Equatable {
        case duplicateInProcess
        case invalidParameter
        case unknown(OSStatus)
    }

    private var hotKeys: [TranslationAction: KS_HotKey] = [:]

    public init() {}

    @discardableResult
    public func start(initial: [TranslationAction: HotkeyConfig?]) -> [TranslationAction: RegisterError] {
        var errors: [TranslationAction: RegisterError] = [:]
        for action in TranslationAction.allCases {
            // If the caller explicitly passes nil for an action, honor that. Otherwise fall back to the default.
            let config: HotkeyConfig?
            if let entry = initial[action] {
                config = entry
            } else {
                config = action.defaultHotkey
            }
            if let err = registerInternal(action: action, config: config) {
                errors[action] = err
            }
        }
        return errors
    }

    public func stop() {
        // KS_HotKey deinit unregisters from Carbon.
        hotKeys.removeAll()
    }

    @discardableResult
    public func reregister(action: TranslationAction, hotkey: HotkeyConfig?) -> RegisterError? {
        // Drop the previous registration first so the same combo can be re-registered without a duplicate error.
        hotKeys[action] = nil
        return registerInternal(action: action, config: hotkey)
    }

    public func pauseAll() {
        KS_HotKeyCenter.shared.pauseAll()
    }

    public func resumeAll() {
        KS_HotKeyCenter.shared.resumeAll()
    }

    private func registerInternal(action: TranslationAction, config: HotkeyConfig?) -> RegisterError? {
        guard let config else { return nil }
        do {
            let hotKey = try KS_HotKey(
                carbonKeyCode: Int(config.keyCode),
                carbonModifiers: Int(config.modifiers),
                onKeyDown: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.onAction?(action)
                    }
                },
                onKeyUp: {}
            )
            hotKeys[action] = hotKey
            return nil
        } catch KS_HotKey.RegisterError.carbonStatus(let status) {
            switch status {
            case OSStatus(eventHotKeyExistsErr): return .duplicateInProcess
            case OSStatus(paramErr):              return .invalidParameter
            default:                              return .unknown(status)
            }
        } catch {
            return .unknown(0)
        }
    }
}
