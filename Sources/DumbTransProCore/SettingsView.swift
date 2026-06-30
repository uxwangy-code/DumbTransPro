import AppKit
import SwiftUI

public struct SettingsView: View {
    private static let fridayTenantLookupURL = URL(string: "https://friday.sankuai.com/budget/serviceManage")!

    @ObservedObject var store: SettingsStore
    @ObservedObject var license: LicenseManager
    let hotkeyManager: HotkeyManager
    private let offlineTranslator: (any OfflineTranslating)?
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    @State private var selectedSection: SettingsPanelSection? = .aiService
    @State private var offlineAvailability: OfflineAvailability?
    @State private var selectedProvider: AIProvider?
    @State private var apiKey: String = ""
    @State private var baseURLOverride: String = ""
    @State private var model: String = ""
    @State private var translationStyle: TranslationStyle
    @State private var isAPIKeyVisible: Bool = false
    @State private var licenseKeyInput: String = ""
    @State private var isActivatingLicense: Bool = false
    @State private var licenseError: String?

    public init(store: SettingsStore, hotkeyManager: HotkeyManager, license: LicenseManager, offlineTranslator: (any OfflineTranslating)? = nil, onClose: (() -> Void)? = nil) {
        self.store = store
        self.license = license
        self.hotkeyManager = hotkeyManager
        self.offlineTranslator = offlineTranslator
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
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionHeader(for: currentSection)
                        selectedSectionContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                footerActions
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 500, idealHeight: 560)
        .task {
            offlineAvailability = await offlineTranslator?.availability()
        }
    }

    /// 当前是否有可用的 AI key（决定土翻/装翻是否可用——离线只做正翻）。
    private var aiAvailable: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Sections

    private var currentSection: SettingsPanelSection {
        selectedSection ?? .aiService
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SettingsPanelSection.allCases) { section in
                sidebarButton(for: section)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .padding(.horizontal, 12)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarButton(for section: SettingsPanelSection) -> some View {
        let state = SettingsPanelSidebarItemState(section: section, selectedSection: currentSection)
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(section.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(state.isSelected ? Color.white : Color.primary)
            .background {
                if state.isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.accessibilityLabel))
        .accessibilityAddTraits(state.isSelected ? .isSelected : [])
        .accessibilityValue(Text(state.accessibilityValue ?? ""))
    }

    private func sectionHeader(for section: SettingsPanelSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch currentSection {
        case .aiService:
            aiServiceSection
        case .translation:
            translationSection
        case .pro:
            licenseSection
        case .feedbackAbout:
            feedbackAboutSection
        }
    }

    private var aiServiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            providerSection

            if let provider = selectedProvider {
                endpointSection(provider: provider)
                apiKeySection(provider: provider)
                modelSection(provider: provider)
            }
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HotkeySection(store: store, hotkeyManager: hotkeyManager)

            Divider()

            translationStyleSection

            if offlineAvailability != nil {
                Divider()
                offlineSection
            }
        }
    }

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
                        Button {
                            openExternalURL(Self.fridayTenantLookupURL)
                        } label: {
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
                let requiresAI = style != .natural
                let isDisabled = requiresAI && !aiAvailable
                Button {
                    translationStyle = style
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: translationStyle == style ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(translationStyle == style ? Color.accentColor : Color.secondary)
                            .frame(width: 16, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(style.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if isDisabled {
                                    Text("需 AI")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(style.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.45 : 1)
            }
            if !aiAvailable {
                Text("未配置 AI key 时仅「正翻」可用（离线设备端翻译）。土翻 / 装翻需要 AI。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("离线翻译")
                .font(.subheadline)
            switch offlineAvailability {
            case .ready:
                Label("已就绪 · 无需联网即可使用「正翻」和 kebab 文件名", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .needsDownload:
                VStack(alignment: .leading, spacing: 6) {
                    Label("离线翻译需要先下载语言包", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    #if canImport(Translation)
                    if #available(macOS 15, *) {
                        // 一键：弹出 Apple 原生下载框，只列中文与英文
                        OfflineLanguageDownloadButton {
                            offlineAvailability = await offlineTranslator?.availability()
                        }
                        .font(.caption)
                    }
                    #endif
                    Button("或在系统设置中手动添加") { openLanguageSettings() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            case .unsupported, .none:
                Label("当前系统不支持离线翻译（需 macOS 15+）", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openLanguageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pro")
                .font(.subheadline)
            if license.tier == .pro {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Pro 已激活" + (license.maskedKey.map { "（\($0)）" } ?? ""))
                        Spacer()
                        Button("停用此设备") {
                            license.deactivate()
                        }
                    }
                    if let detail = license.proStatusDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(license.lastVerificationProblem == nil ? Color.secondary : Color.orange)
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
                    Button {
                        openExternalURL(LicensePurchase.url())
                    } label: {
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
                Text("如果激活时提示网络不可用，可以尝试挂🪜后重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feedbackAboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("反馈")
                    .font(.subheadline)
                Button {
                    openFeedbackMail()
                } label: {
                    Label("邮件反馈", systemImage: "envelope")
                }
                Text("会打开你的默认邮件客户端，并预填版本、系统、服务商和授权状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("匿名使用数据")
                    .font(.subheadline)
                Toggle(isOn: Binding(
                    get: { store.shareAnonymousUsageData },
                    set: { store.setShareAnonymousUsageData($0) }
                )) {
                    Text("发送匿名使用数据")
                }
                .toggleStyle(.switch)
                Text("用于帮助我们改进服务。只发送匿名使用状态，不发送原文、译文、API Key、License Key、剪贴板、用户输入或个人身份信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("关于")
                    .font(.subheadline)
                Label("版本 \(currentFeedbackContext.appVersion)", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                aboutLinks
            }
        }
    }

    private var aboutLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openExternalURL(URL(string: "https://uxwangy-code.github.io/DumbTransPro/")!)
            } label: {
                Label("官网", systemImage: "safari")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Button {
                openExternalURL(URL(string: "https://github.com/uxwangy-code/DumbTransPro")!)
            } label: {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Button {
                openExternalURL(URL(string: "https://uxwangy-code.github.io/DumbTransPro/privacy.html")!)
            } label: {
                Label("隐私政策", systemImage: "hand.raised")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    private var footerActions: some View {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var currentFeedbackContext: SettingsFeedbackContext {
        SettingsFeedbackMail.context(
            activeProviderName: selectedProvider?.displayName ?? store.activeProvider?.displayName,
            licenseTier: license.tier
        )
    }

    private func openFeedbackMail() {
        openExternalURL(SettingsFeedbackMail.url(context: currentFeedbackContext))
    }

    private func openExternalURL(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open(url, configuration: configuration) { app, _ in
            guard let app else { return }
            DispatchQueue.main.async {
                app.activate(options: [.activateAllWindows])
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
