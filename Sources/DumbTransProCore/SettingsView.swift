import SwiftUI

public struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let hotkeyManager: HotkeyManager
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    @State private var selectedProvider: AIProvider?
    @State private var apiKey: String = ""
    @State private var baseURLOverride: String = ""
    @State private var model: String = ""
    @State private var translationStyle: TranslationStyle
    @State private var isAPIKeyVisible: Bool = false

    public init(store: SettingsStore, hotkeyManager: HotkeyManager, onClose: (() -> Void)? = nil) {
        self.store = store
        self.hotkeyManager = hotkeyManager
        self.onClose = onClose
        _selectedProvider = State(initialValue: store.activeProvider)
        _translationStyle = State(initialValue: store.translationStyle)
        if let active = store.activeProvider {
            let cfg = store.config(for: active)
            _apiKey = State(initialValue: cfg.apiKey)
            _baseURLOverride = State(initialValue: cfg.baseURL.isEmpty ? active.defaultBaseURL : cfg.baseURL)
            _model = State(initialValue: cfg.model.isEmpty ? active.defaultModel : cfg.model)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("瞎翻 Pro 设置")
                .font(.headline)

            providerSection

            if let provider = selectedProvider {
                endpointSection(provider: provider)
                apiKeySection(provider: provider)
                modelSection(provider: provider)
            }

            Divider()

            HotkeySection(store: store, hotkeyManager: hotkeyManager)

            Divider()

            translationStyleSection

            HStack {
                Spacer()
                Button("取消") {
                    onClose?()
                    dismiss()
                }
                Button("保存") {
                    saveAndClose()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProvider == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Sections

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 服务商")
                .font(.subheadline)
            Picker("", selection: $selectedProvider) {
                Text("请选择服务商").tag(AIProvider?.none)
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(AIProvider?.some(provider))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 240, alignment: .leading)
            .onChange(of: selectedProvider) { newValue in
                loadFields(for: newValue)
            }
        }
    }

    private func endpointSection(provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Endpoint")
                .font(.subheadline)
            HStack(spacing: 8) {
                TextField(provider.defaultBaseURL.isEmpty ? "https://..." : provider.defaultBaseURL, text: $baseURLOverride)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 340)
                if !provider.endpointPresets.isEmpty {
                    Menu {
                        ForEach(provider.endpointPresets, id: \.url) { preset in
                            Button(preset.label) { baseURLOverride = preset.url }
                        }
                    } label: {
                        Text("快捷选择")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private func apiKeySection(provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.apiKeyFieldLabel)
                .font(.subheadline)
            HStack(spacing: 8) {
                Group {
                    if isAPIKeyVisible {
                        TextField("输入\(provider.apiKeyFieldLabel)...", text: $apiKey)
                    } else {
                        SecureField("输入\(provider.apiKeyFieldLabel)...", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 370)

                Button {
                    isAPIKeyVisible.toggle()
                } label: {
                    Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(isAPIKeyVisible ? "隐藏" : "显示")
            }
            if let hint = provider.apiKeyHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelSection(provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.subheadline)
            HStack(spacing: 8) {
                TextField(provider.defaultModel.isEmpty ? "模型名称" : provider.defaultModel, text: $model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 340)
                if !provider.modelPresets.isEmpty {
                    Menu {
                        ForEach(provider.modelPresets, id: \.id) { preset in
                            Button(preset.label) { model = preset.id }
                        }
                    } label: {
                        Text("快捷选择")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            Text("建议使用非推理模型,提高翻译速度")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let hint = provider.modelHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var translationStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("翻译风格")
                .font(.subheadline)
            ForEach(TranslationStyle.allCases) { style in
                Button {
                    translationStyle = style
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: translationStyle == style ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(translationStyle == style ? Color.accentColor : Color.secondary)
                            .frame(width: 16, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(style.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func loadFields(for provider: AIProvider?) {
        guard let provider else {
            apiKey = ""
            baseURLOverride = ""
            model = ""
            return
        }
        let cfg = store.config(for: provider)
        apiKey = cfg.apiKey
        baseURLOverride = cfg.baseURL.isEmpty ? provider.defaultBaseURL : cfg.baseURL
        model = cfg.model.isEmpty ? provider.defaultModel : cfg.model
    }

    private func saveAndClose() {
        guard let provider = selectedProvider else { return }

        let trimmedBaseURL = baseURLOverride.trimmingCharacters(in: .whitespaces)
        let resolvedBaseURL = (trimmedBaseURL == provider.defaultBaseURL) ? "" : trimmedBaseURL

        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        let resolvedModel = (trimmedModel == provider.defaultModel) ? "" : trimmedModel

        let config = ProviderConfig(
            apiKey: apiKey,
            baseURL: resolvedBaseURL,
            model: resolvedModel
        )
        store.updateConfig(provider, config)
        store.setActiveProvider(provider)
        store.setTranslationStyle(translationStyle)
        onClose?()
        dismiss()
    }
}
