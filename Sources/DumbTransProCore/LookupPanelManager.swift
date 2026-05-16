import AppKit
import Combine
import SwiftUI

@MainActor
final class LookupPanelManager {
    private static let slowHintCharThreshold = 400
    private static let slowHintDelayNanos: UInt64 = 5_000_000_000

    private var panel: NSPanel?
    private var hostingController: NSHostingController<LookupPanelView>?
    private var panelState: LookupPanelState?
    private var translationTask: Task<Void, Never>?
    private var slowHintTask: Task<Void, Never>?
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

        // Resize panel as state changes (loading → translation, expand toggle, error, slow hint)
        let loadingPair = Publishers.CombineLatest(state.$isLoading, state.$isSlowLoading)
        Publishers.CombineLatest4(
            loadingPair,
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

        if originalText.count > Self.slowHintCharThreshold {
            slowHintTask = Task { [weak state] in
                try? await Task.sleep(nanoseconds: Self.slowHintDelayNanos)
                guard !Task.isCancelled, let state, state.isLoading else { return }
                state.isSlowLoading = true
            }
        }

        translationTask = Task { [weak self, weak state] in
            guard let state else { return }
            let service = TranslateService(
                apiKey: settingsStore.apiKey,
                baseURL: settingsStore.baseURL,
                model: settingsStore.model
            )
            do {
                let result = try await service.lookup(originalText, style: settingsStore.translationStyle)
                guard !Task.isCancelled else { return }
                state.translation = result.text
                state.didFallback = result.didFallback
                state.isLoading = false
                state.isSlowLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                state.error = error.localizedDescription
                state.isLoading = false
                state.isSlowLoading = false
            }
            self?.slowHintTask?.cancel()
            self?.slowHintTask = nil
        }
    }

    private func resizeToFitContent() {
        guard let panel, let controller = hostingController else { return }
        // Force a layout pass so fittingSize reflects current state
        controller.view.layoutSubtreeIfNeeded()
        let fitting = controller.view.fittingSize
        let screenCap = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let maxHeight = min(screenCap * 0.85, 680)
        let newHeight = min(max(fitting.height, 180), maxHeight)
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
        slowHintTask?.cancel()
        slowHintTask = nil
        stateObservers.removeAll()
        panel?.close()
        panel = nil
        hostingController = nil
        panelState = nil
    }
}
