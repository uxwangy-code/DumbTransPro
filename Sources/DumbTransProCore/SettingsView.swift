import AppKit
import SwiftUI

public struct SettingsView: View {
    private static let fridayTenantLookupURL = URL(string: "https://friday.sankuai.com/budget/serviceManage")!

    @ObservedObject var store: SettingsStore
    @ObservedObject var license: LicenseManager
    let hotkeyManager: HotkeyManager
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    @State private var selectedProvider: AIProvider?
    @State private var apiKey: String = ""
    @State private var baseURLOverride: String = ""
    @State private var model: String = ""
    @State private var translationStyle: TranslationStyle
    @State private var isAPIKeyVisible: Bool = false
    @State private var licenseKeyInput: String = ""
    @State private var isActivatingLicense: Bool = false
    @State private var licenseError: String?

    public init(store: SettingsStore, hotkeyManager: HotkeyManager, license: LicenseManager, onClose: (() -> Void)? = nil) {
        self.store = store
        self.license = license
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

            Divider()

            licenseSection

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
                ForEach(visibleProviders) { provider in
                    Text(providerLabel(provider)).tag(AIProvider?.some(provider))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 240, alignment: .leading)
            .onChange(of: selectedProvider) { newValue in
                loadFields(for: newValue)
            }
            if license.tier == .free {
                Text("免费版可用 \(LicenseManager.freeProviderNames)；带 🔒 的服务商需要 Pro。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// friday 是内部环境专用 provider，只对已经配置过它的老用户可见
    private var visibleProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            guard provider == .friday else { return true }
            return store.activeProvider == .friday || !store.config(for: .friday).apiKey.isEmpty
        }
    }

    private func providerLabel(_ provider: AIProvider) -> String {
        if license.tier == .free && !LicenseManager.freeProviders.contains(provider) {
            return provider.displayName + " 🔒"
        }
        return provider.displayName
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
                        LiveTextField(
                            text: $apiKey,
                            placeholder: "输入\(provider.apiKeyFieldLabel)...",
                            isSecure: false
                        )
                    } else {
                        LiveTextField(
                            text: $apiKey,
                            placeholder: "输入\(provider.apiKeyFieldLabel)...",
                            isSecure: true
                        )
                    }
                }
                .id(isAPIKeyVisible)
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
                HStack(spacing: 6) {
                    Text(hint)
                        .foregroundStyle(.secondary)
                    if provider == .friday {
                        Link(destination: Self.fridayTenantLookupURL) {
                            HStack(spacing: 2) {
                                Text("前往查找")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("打开 Friday 控制台")
                    }
                }
                .font(.caption)
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

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pro")
                .font(.subheadline)
            if license.tier == .pro {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Pro 已激活" + (license.maskedKey.map { "（\($0)）" } ?? ""))
                    Spacer()
                    Button("停用此设备") {
                        license.deactivate()
                    }
                }
            } else {
                Text("免费版：\(LicenseManager.freeProviderNames)，每日 \(LicenseManager.freeDailyLimit) 次。Pro 一次买断，解锁全部服务商 + 不限次数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("输入 License Key...", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    Button(isActivatingLicense ? "验证中..." : "激活") {
                        activateLicense()
                    }
                    .disabled(isActivatingLicense || licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Link(destination: GumroadLicenseVerifier.purchaseURL) {
                        HStack(spacing: 2) {
                            Text("获取 License")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                if let licenseError {
                    Text(licenseError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func activateLicense() {
        isActivatingLicense = true
        licenseError = nil
        let key = licenseKeyInput
        Task { @MainActor in
            do {
                try await license.activate(key: key)
                licenseKeyInput = ""
            } catch {
                licenseError = error.localizedDescription
            }
            isActivatingLicense = false
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
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
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

private struct LiveTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? NSSecureTextField() : NSTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
