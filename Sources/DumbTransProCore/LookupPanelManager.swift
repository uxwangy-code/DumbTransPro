import AppKit
import Combine
import SwiftUI

@MainActor
final class LookupPanelManager {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<LookupPanelView>?
    private var panelState: LookupPanelState?
    private var translationTask: Task<Void, Never>?
    private var stateObservers: Set<AnyCancellable> = []

    func show(originalText: String, settingsStore: SettingsStore) {
        close()

        let state = LookupPanelState(originalText: originalText, modelName: settingsStore.model)
        state.onClose = { [weak self] in self?.close() }
        panelState = state

        let view = LookupPanelView(state: state)
        let controller = NSHostingController(rootView: view)
        if #available(macOS 13.0, *) {
            controller.sizingOptions = [.preferredContentSize]
        }
        hostingController = controller

        let initial = controller.view.fittingSize

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: LookupPanelView.panelWidth, height: max(initial.height, 180)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.contentViewController = controller
        p.center()
        p.orderFront(nil)
        panel = p

        // Resize panel as state changes (loading → translation, expand toggle, error)
        Publishers.CombineLatest4(
            state.$isLoading,
            state.$translation,
            state.$isOriginalExpanded,
            state.$error
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.resizeToFitContent()
        }
        .store(in: &stateObservers)

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
            _ = self
        }
    }

    private func resizeToFitContent() {
        guard let panel, let controller = hostingController else { return }
        // Force a layout pass so fittingSize reflects current state
        controller.view.layoutSubtreeIfNeeded()
        let fitting = controller.view.fittingSize
        let newHeight = max(fitting.height, 180)
        var frame = panel.frame
        // Keep the top of the panel anchored as the content grows downward
        let delta = newHeight - frame.size.height
        frame.size.height = newHeight
        frame.size.width = LookupPanelView.panelWidth
        frame.origin.y -= delta
        panel.setFrame(frame, display: true, animate: true)
    }

    func close() {
        translationTask?.cancel()
        translationTask = nil
        stateObservers.removeAll()
        panel?.close()
        panel = nil
        hostingController = nil
        panelState = nil
    }
}
