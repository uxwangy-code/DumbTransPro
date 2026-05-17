import SwiftUI
import AppKit

public struct HotkeySection: View {
    @ObservedObject var store: SettingsStore
    let hotkeyManager: HotkeyManager

    public init(store: SettingsStore, hotkeyManager: HotkeyManager) {
        self.store = store
        self.hotkeyManager = hotkeyManager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.subheadline)

            ForEach(TranslationAction.allCases, id: \.self) { action in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.body)
                        Text(actionSubtitle(action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotkeyChipView(
                        config: store.hotkey(for: action),
                        defaultHotkey: action.defaultHotkey,
                        detectConflict: { detectConflict($0, for: action) },
                        onCommit: { commit($0, for: action) },
                        onRecordingStarted: { hotkeyManager.pauseAll() },
                        onRecordingEnded:   { hotkeyManager.resumeAll() }
                    )
                }
            }
        }
    }

    private func actionSubtitle(_ action: TranslationAction) -> String {
        switch action {
        case .rewriteToEnglish: return "将选中文译为英文并粘贴回去"
        case .lookup:           return "选中后弹出查词面板"
        }
    }

    private func detectConflict(_ config: HotkeyConfig, for action: TranslationAction) -> ConflictKind {
        // 1. App-internal: another action already uses the same combo.
        for other in TranslationAction.allCases where other != action {
            if store.hotkey(for: other) == config {
                return .appInternal(otherActionTitle: other.title)
            }
        }
        // 2. App main menu — beaten by the foreground app's menu items.
        if let item = KS_MainMenu.itemMatching(
            carbonKeyCode: Int(config.keyCode),
            carbonModifiers: Int(config.modifiers)
        ) {
            return .mainMenu(itemTitle: item.title)
        }
        // 3. System-registered symbolic hotkeys (Mission Control, Spotlight, etc.).
        if KS_SystemShortcuts.contains(
            carbonKeyCode: Int(config.keyCode),
            carbonModifiers: Int(config.modifiers)
        ) {
            return .system
        }
        return .none
    }

    private func commit(_ config: HotkeyConfig?, for action: TranslationAction) {
        store.setHotkey(config, for: action)
        _ = hotkeyManager.reregister(action: action, hotkey: config)
    }
}
