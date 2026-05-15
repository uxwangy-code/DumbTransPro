import AppKit
import SwiftUI

@MainActor
final class LookupPanelManager {
    private var panel: NSPanel?
    private var panelState: LookupPanelState?
    private var translationTask: Task<Void, Never>?

    func show(originalText: String, settingsStore: SettingsStore) {
        close()

        let state = LookupPanelState(originalText: originalText, modelName: settingsStore.model)
        state.onClose = { [weak self] in self?.close() }
        panelState = state

        let view = LookupPanelView(state: state)
        let hosting = NSHostingView(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.contentView = hosting
        p.center()
        p.orderFront(nil)
        panel = p

        translationTask = Task { [weak self, weak state] in
            guard let state else { return }
            let service = TranslateService(
                apiKey: settingsStore.apiKey,
                baseURL: settingsStore.baseURL,
                model: settingsStore.model
            )
            do {
                let result = try await service.lookup(originalText)
                guard !Task.isCancelled else { return }
                state.translation = result
                state.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                state.error = error.localizedDescription
                state.isLoading = false
            }
            _ = self // keep manager alive during task
        }
    }

    func close() {
        translationTask?.cancel()
        translationTask = nil
        panel?.close()
        panel = nil
        panelState = nil
    }
}
