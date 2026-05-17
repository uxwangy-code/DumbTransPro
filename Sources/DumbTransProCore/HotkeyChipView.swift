import SwiftUI
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyChipCoordinator: ObservableObject {
    @Published var state: RecorderState
    private var monitor: KS_LocalEventMonitor?

    let defaultHotkey: HotkeyConfig
    var detectConflict: (HotkeyConfig) -> ConflictKind
    var onCommit: (HotkeyConfig?) -> Void
    var onRecordingStarted: () -> Void
    var onRecordingEnded: () -> Void

    init(
        config: HotkeyConfig?,
        defaultHotkey: HotkeyConfig,
        detectConflict: @escaping (HotkeyConfig) -> ConflictKind,
        onCommit: @escaping (HotkeyConfig?) -> Void,
        onRecordingStarted: @escaping () -> Void,
        onRecordingEnded: @escaping () -> Void
    ) {
        self.state = (config == nil) ? .cleared : .resting
        self.defaultHotkey = defaultHotkey
        self.detectConflict = detectConflict
        self.onCommit = onCommit
        self.onRecordingStarted = onRecordingStarted
        self.onRecordingEnded = onRecordingEnded
    }

    func dispatch(_ event: RecorderEvent) {
        let (newState, effects) = HotkeyChipReducer.reduce(state: state, event: event)
        for effect in effects { apply(effect) }
        state = newState
    }

    /// Called by the parent when the underlying config changes externally (e.g. resetHotkey from elsewhere).
    func syncExternalConfig(_ config: HotkeyConfig?) {
        // Don't disturb an in-progress recording or conflict state.
        switch state {
        case .recording, .conflict: return
        default: break
        }
        state = (config == nil) ? .cleared : .resting
    }

    private func apply(_ effect: RecorderEffect) {
        switch effect {
        case .installMonitor: installMonitor()
        case .removeMonitor:  removeMonitor()
        case .pauseAllHotkeys: onRecordingStarted()
        case .resumeAllHotkeys: onRecordingEnded()
        case .commit(let cfg): onCommit(cfg)
        case .commitDefault:   onCommit(defaultHotkey)
        case .beep: NSSound.beep()
        case .moveFocusToNextResponder:
            NSApp.keyWindow?.selectNextKeyView(nil)
        }
    }

    private func installMonitor() {
        let monitor = KS_LocalEventMonitor(events: [.keyDown, .flagsChanged, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseUp, .rightMouseUp:
                self.dispatch(.focusLost)
                return event
            case .keyDown:
                return self.handleKeyDown(event)
            case .flagsChanged:
                return nil
            default:
                return event
            }
        }
        monitor.start()
        self.monitor = monitor
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == UInt16(kVK_Escape) {
            dispatch(.escPressed)
            return nil
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            dispatch(.deleteOrBackspacePressed)
            return nil
        }
        if event.keyCode == UInt16(kVK_Tab) {
            dispatch(.tabPressed)
            return event  // bubble for focus traversal
        }
        // Require at least one of {⌘, ⌃, ⌥}.
        let strippedMods = event.modifierFlags.subtracting([.shift, .function])
        guard !strippedMods.isEmpty else {
            dispatch(.invalidKeyDown)
            return nil
        }
        let cfg = HotkeyConfig(
            keyCode: UInt32(event.keyCode),
            modifiers: UInt32(event.modifierFlags.carbonRepresentation)
        )
        let conflict = detectConflict(cfg)
        dispatch(.keyDown(config: cfg, conflict: conflict))
        return nil
    }

    private func removeMonitor() {
        monitor?.stop()
        monitor = nil
    }
}

public struct HotkeyChipView: View {
    @StateObject private var coordinator: HotkeyChipCoordinator
    private let externalConfig: HotkeyConfig?

    public init(
        config: HotkeyConfig?,
        defaultHotkey: HotkeyConfig,
        detectConflict: @escaping (HotkeyConfig) -> ConflictKind,
        onCommit: @escaping (HotkeyConfig?) -> Void,
        onRecordingStarted: @escaping () -> Void,
        onRecordingEnded: @escaping () -> Void
    ) {
        self.externalConfig = config
        _coordinator = StateObject(wrappedValue: HotkeyChipCoordinator(
            config: config,
            defaultHotkey: defaultHotkey,
            detectConflict: detectConflict,
            onCommit: onCommit,
            onRecordingStarted: onRecordingStarted,
            onRecordingEnded: onRecordingEnded
        ))
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            chip
            footnote
        }
        .onChange(of: externalConfig) { newValue in
            coordinator.syncExternalConfig(newValue)
        }
    }

    @ViewBuilder
    private var chip: some View {
        switch coordinator.state {
        case .resting, .warning:
            HStack(spacing: 6) {
                Text(externalConfig?.displayString ?? coordinator.defaultHotkey.displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                Button { coordinator.dispatch(.clearClicked) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground(borderColor: borderColor))
            .help("更改快捷键")
            .onTapGesture { coordinator.dispatch(.chipClicked) }

        case .recording, .conflict:
            HStack(spacing: 6) {
                Text("按下快捷键…")
                    .foregroundStyle(.secondary)
                Button { coordinator.dispatch(.resetClicked) } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground(borderColor: borderColor))

        case .cleared:
            Button { coordinator.dispatch(.chipClicked) } label: {
                Text("点击设置")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: 110)
                    .background(chipBackground(borderColor: Color.secondary.opacity(0.3)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var footnote: some View {
        switch coordinator.state {
        case .conflict(let label, _):
            Text(label).font(.caption).foregroundStyle(.red)
        case .warning(let label):
            Text(label).font(.caption).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch coordinator.state {
        case .conflict: return .red
        case .recording: return .accentColor
        case .warning:  return .orange.opacity(0.6)
        default:        return Color.secondary.opacity(0.3)
        }
    }

    private func chipBackground(borderColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1.5)
            )
            .frame(minWidth: 110)
    }
}
