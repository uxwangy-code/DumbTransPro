import Foundation

public indirect enum RecorderState: Equatable, Sendable {
    case resting
    case recording(returnTo: RecorderState)
    case cleared
    case conflict(label: String, returnTo: RecorderState)
    case warning(label: String)
}

public enum ConflictKind: Equatable, Sendable {
    case none
    case appInternal(otherActionTitle: String)
    case system
    case mainMenu(itemTitle: String)
}

public enum RecorderEvent: Equatable, Sendable {
    case chipClicked
    case clearClicked
    case escPressed
    case deleteOrBackspacePressed
    case tabPressed
    case resetClicked
    case focusLost
    case keyDown(config: HotkeyConfig, conflict: ConflictKind)
    case invalidKeyDown
}

public enum RecorderEffect: Equatable, Sendable {
    case installMonitor
    case removeMonitor
    case pauseAllHotkeys
    case resumeAllHotkeys
    case commit(HotkeyConfig?)
    case commitDefault
    case beep
    case moveFocusToNextResponder
}

public enum HotkeyChipReducer {
    public static func reduce(state: RecorderState, event: RecorderEvent) -> (RecorderState, [RecorderEffect]) {
        switch (state, event) {

        // From resting / warning
        case (.resting, .chipClicked), (.warning, .chipClicked):
            return (.recording(returnTo: .resting), [.installMonitor, .pauseAllHotkeys])

        case (.resting, .clearClicked), (.warning, .clearClicked):
            return (.cleared, [.commit(nil)])

        // From cleared
        case (.cleared, .chipClicked):
            return (.recording(returnTo: .cleared), [.installMonitor, .pauseAllHotkeys])

        // From recording — exit paths
        case (.recording(let returnTo), .escPressed):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.recording, .deleteOrBackspacePressed):
            return (.cleared, [.commit(nil), .removeMonitor, .resumeAllHotkeys])

        case (.recording(let returnTo), .tabPressed):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys, .moveFocusToNextResponder])

        case (.recording(let returnTo), .focusLost):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.recording, .resetClicked):
            return (.resting, [.removeMonitor, .resumeAllHotkeys, .commitDefault])

        case (.recording, .invalidKeyDown):
            return (state, [.beep])

        case (.recording(let returnTo), .keyDown(let cfg, let conflict)):
            switch conflict {
            case .none:
                return (.resting, [.removeMonitor, .resumeAllHotkeys, .commit(cfg)])
            case .appInternal(let other):
                return (
                    .conflict(label: "已被『\(other)』使用", returnTo: returnTo),
                    []
                )
            case .system:
                return (
                    .warning(label: "可能与系统快捷键冲突,可能不生效"),
                    [.removeMonitor, .resumeAllHotkeys, .commit(cfg)]
                )
            case .mainMenu(let title):
                return (
                    .warning(label: "已被菜单项『\(title)』占用,前台 app 优先"),
                    [.removeMonitor, .resumeAllHotkeys, .commit(cfg)]
                )
            }

        // From conflict — exit / re-record
        case (.conflict(_, let returnTo), .escPressed),
             (.conflict(_, let returnTo), .focusLost):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.conflict(_, let returnTo), .keyDown(let cfg, let conflict)):
            // Treat as if we're back in recording: delegate by re-entering.
            return reduce(state: .recording(returnTo: returnTo), event: .keyDown(config: cfg, conflict: conflict))

        case (.conflict, .invalidKeyDown):
            return (state, [.beep])

        // Unhandled combinations: no-op.
        default:
            return (state, [])
        }
    }
}
