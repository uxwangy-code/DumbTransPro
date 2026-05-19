import Foundation

private let keychainService = "com.whimsycode.dumbtrans-pro"
private let legacyKeychainAccount = "api-key"
private let legacyProviderKey = "provider"
private let legacyCustomBaseURLKey = "customBaseURL"
private let legacyCustomModelKey = "customModel"
private let activeProviderKey = "activeProvider"
private let providerOverridesKey = "providerOverrides"
private let translationStyleKey = "translationStyle"

public struct ModelPreset: Sendable, Hashable {
    public let id: String
    public let label: String
    public let isRecommended: Bool

    public init(id: String, label: String? = nil, isRecommended: Bool = false) {
        self.id = id
        self.label = label ?? id
        self.isRecommended = isRecommended
    }
}

public struct EndpointPreset: Sendable, Hashable {
    public let url: String
    public let label: String

    public init(url: String, label: String? = nil) {
        self.url = url
        self.label = label ?? url
    }
}

public enum AIProvider: String, CaseIterable, Sendable, Identifiable {
    case openai
    case zhipu
    case deepseek
    case kimi
    case minimax
    case qwen
    case doubao
    case friday
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .zhipu: return "智谱 GLM"
        case .deepseek: return "DeepSeek"
        case .kimi: return "Kimi"
        case .minimax: return "MiniMax"
        case .qwen: return "通义千问"
        case .doubao: return "豆包"
        case .friday: return "Friday"
        case .custom: return "自定义"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .kimi: return "https://api.moonshot.cn/v1"
        case .minimax: return "https://api.minimax.io/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .friday: return "https://aigc.sankuai.com/v1/openai/native"
        case .custom: return ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .zhipu: return "glm-4-flash"
        case .deepseek: return "deepseek-v4-flash"
        case .kimi: return "moonshot-v1-8k"
        case .minimax: return "MiniMax-M2.7-highspeed"
        case .qwen: return "qwen-turbo"
        case .doubao: return "doubao-lite-32k"
        case .friday: return "deepseek-v4-flash"
        case .custom: return ""
        }
    }

    public var endpointPresets: [EndpointPreset] {
        switch self {
        case .openai:
            return [
                EndpointPreset(url: "https://api.openai.com/v1", label: "https://api.openai.com/v1 (官方)"),
            ]
        case .zhipu:
            return [
                EndpointPreset(url: "https://open.bigmodel.cn/api/paas/v4", label: "/api/paas/v4 (按量付费/资源包)"),
                EndpointPreset(url: "https://open.bigmodel.cn/api/coding/paas/v4", label: "/api/coding/paas/v4 (Coding Plan)"),
                EndpointPreset(url: "https://api.z.ai/api/paas/v4", label: "api.z.ai/api/paas/v4 (国际版)"),
            ]
        case .deepseek:
            return [
                EndpointPreset(url: "https://api.deepseek.com/v1", label: "/v1 (生产)"),
                EndpointPreset(url: "https://api.deepseek.com/beta", label: "/beta (Beta 功能)"),
            ]
        case .kimi:
            return [
                EndpointPreset(url: "https://api.moonshot.cn/v1", label: "api.moonshot.cn/v1 (国内)"),
                EndpointPreset(url: "https://api.moonshot.ai/v1", label: "api.moonshot.ai/v1 (国际)"),
            ]
        case .minimax:
            return [
                EndpointPreset(url: "https://api.minimax.io/v1", label: "api.minimax.io/v1 (国际)"),
                EndpointPreset(url: "https://api.minimaxi.com/v1", label: "api.minimaxi.com/v1 (国内)"),
            ]
        case .qwen:
            return [
                EndpointPreset(url: "https://dashscope.aliyuncs.com/compatible-mode/v1", label: "dashscope.aliyuncs.com (北京)"),
                EndpointPreset(url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", label: "dashscope-intl (新加坡)"),
                EndpointPreset(url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1", label: "dashscope-us (弗吉尼亚)"),
            ]
        case .doubao:
            return [
                EndpointPreset(url: "https://ark.cn-beijing.volces.com/api/v3", label: "火山方舟 /api/v3"),
            ]
        case .friday:
            return [
                EndpointPreset(url: "https://aigc.sankuai.com/v1/openai/native", label: "默认 endpoint"),
            ]
        case .custom:
            return []
        }
    }

    public var apiKeyFieldLabel: String {
        self == .friday ? "APP ID" : "API Key"
    }

    public var apiKeyHint: String? {
        self == .friday ? "可以去 Friday 控制台查找租户 ID" : nil
    }

    public var modelHint: String? {
        switch self {
        case .friday: return "需要模型的 RPM 大于 0,可以在 Friday 模型广场查找"
        case .doubao: return "可直接填模型名,或填火山方舟控制台的推理接入点 ID(ep-xxxxxx)"
        default: return nil
        }
    }

    public var modelPresets: [ModelPreset] {
        switch self {
        case .openai:
            return [
                ModelPreset(id: "gpt-4o", label: "gpt-4o (通用旗舰)"),
                ModelPreset(id: "gpt-4o-mini", label: "gpt-4o-mini (推荐)", isRecommended: true),
                ModelPreset(id: "gpt-4-turbo", label: "gpt-4-turbo"),
            ]
        case .zhipu:
            return [
                ModelPreset(id: "glm-4-airx", label: "glm-4-airx (极速通用)"),
                ModelPreset(id: "glm-4-air", label: "glm-4-air"),
                ModelPreset(id: "glm-4-flash", label: "glm-4-flash (推荐)", isRecommended: true),
                ModelPreset(id: "glm-4-long", label: "glm-4-long (长上下文)"),
            ]
        case .deepseek:
            return [
                ModelPreset(id: "deepseek-v4-flash", label: "deepseek-v4-flash (推荐)", isRecommended: true),
                ModelPreset(id: "deepseek-chat", label: "deepseek-chat (经典)"),
            ]
        case .kimi:
            return [
                ModelPreset(id: "moonshot-v1-128k", label: "moonshot-v1-128k (长上下文)"),
                ModelPreset(id: "moonshot-v1-32k", label: "moonshot-v1-32k"),
                ModelPreset(id: "moonshot-v1-8k", label: "moonshot-v1-8k (推荐)", isRecommended: true),
            ]
        case .minimax:
            return [
                ModelPreset(id: "MiniMax-M2.7-highspeed", label: "M2.7-highspeed (推荐,非推理)", isRecommended: true),
                ModelPreset(id: "MiniMax-M2.5-highspeed", label: "M2.5-highspeed (非推理)"),
                ModelPreset(id: "MiniMax-M2.1-highspeed", label: "M2.1-highspeed (非推理)"),
            ]
        case .qwen:
            return [
                ModelPreset(id: "qwen-turbo", label: "qwen-turbo (推荐,极速便宜)", isRecommended: true),
                ModelPreset(id: "qwen-flash", label: "qwen-flash (快速)"),
                ModelPreset(id: "qwen-plus", label: "qwen-plus (通用)"),
                ModelPreset(id: "qwen-max", label: "qwen-max (旗舰)"),
            ]
        case .doubao:
            return [
                ModelPreset(id: "doubao-lite-32k", label: "doubao-lite-32k (推荐)", isRecommended: true),
                ModelPreset(id: "doubao-lite-128k", label: "doubao-lite-128k (长上下文)"),
                ModelPreset(id: "doubao-pro-32k", label: "doubao-pro-32k (更高质量)"),
                ModelPreset(id: "doubao-pro-128k", label: "doubao-pro-128k"),
            ]
        case .friday, .custom:
            return []
        }
    }
}

public struct ProviderConfig: Sendable, Equatable, Codable {
    public var apiKey: String
    public var baseURL: String
    public var model: String

    public init(apiKey: String = "", baseURL: String = "", model: String = "") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var activeProvider: AIProvider?
    @Published public var translationStyle: TranslationStyle = .natural
    @Published public private(set) var hotkeys: [TranslationAction: HotkeyConfig?] = [:]

    private var configs: [AIProvider: ProviderConfig] = [:]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSettings()
        loadHotkeys()
    }

    public func loadSettings() {
        migrateLegacyIfNeeded()

        for provider in AIProvider.allCases {
            let baseURL = defaults.string(forKey: overrideBaseURLKey(provider)) ?? ""
            let model = defaults.string(forKey: overrideModelKey(provider)) ?? ""
            let apiKey = (try? KeychainHelper.load(service: keychainService, account: keychainAccount(for: provider))) ?? ""
            configs[provider] = ProviderConfig(apiKey: apiKey, baseURL: baseURL, model: model)
        }

        if let raw = defaults.string(forKey: activeProviderKey),
           let provider = AIProvider(rawValue: raw) {
            activeProvider = provider
        } else {
            activeProvider = nil
        }

        if let raw = defaults.string(forKey: translationStyleKey),
           let style = TranslationStyle(rawValue: raw) {
            translationStyle = style
        } else {
            translationStyle = .natural
        }
    }

    private func loadHotkeys() {
        var map: [TranslationAction: HotkeyConfig?] = [:]
        for action in TranslationAction.allCases {
            map.updateValue(readHotkey(action), forKey: action)
        }
        hotkeys = map
    }

    private func readHotkey(_ action: TranslationAction) -> HotkeyConfig? {
        let key = hotkeyKey(action)
        guard defaults.object(forKey: key) != nil else {
            return action.defaultHotkey
        }
        guard let data = defaults.data(forKey: key), !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(HotkeyConfig.self, from: data)
    }

    public func hotkey(for action: TranslationAction) -> HotkeyConfig? {
        if let entry = hotkeys[action] { return entry }
        return action.defaultHotkey
    }

    public func setHotkey(_ config: HotkeyConfig?, for action: TranslationAction) {
        hotkeys.updateValue(config, forKey: action)
        let key = hotkeyKey(action)
        if let config, let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set(Data(), forKey: key)
        }
    }

    public func resetHotkey(for action: TranslationAction) {
        hotkeys.updateValue(action.defaultHotkey, forKey: action)
        defaults.removeObject(forKey: hotkeyKey(action))
    }

    private func hotkeyKey(_ action: TranslationAction) -> String {
        "hotkey.\(action.persistenceKey)"
    }

    public func config(for provider: AIProvider) -> ProviderConfig {
        configs[provider] ?? ProviderConfig()
    }

    public func updateConfig(_ provider: AIProvider, _ config: ProviderConfig) {
        configs[provider] = config
        persistConfig(provider: provider, config: config)
    }

    public func setActiveProvider(_ provider: AIProvider) {
        activeProvider = provider
        defaults.set(provider.rawValue, forKey: activeProviderKey)
    }

    public func setTranslationStyle(_ style: TranslationStyle) {
        translationStyle = style
        defaults.set(style.rawValue, forKey: translationStyleKey)
    }

    public var apiKey: String {
        guard let provider = activeProvider else { return "" }
        return config(for: provider).apiKey
    }

    public var baseURL: String {
        guard let provider = activeProvider else { return "" }
        let override = config(for: provider).baseURL
        return override.isEmpty ? provider.defaultBaseURL : override
    }

    public var model: String {
        guard let provider = activeProvider else { return "" }
        let override = config(for: provider).model
        return override.isEmpty ? provider.defaultModel : override
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func persistConfig(provider: AIProvider, config: ProviderConfig) {
        let trimmedKey = config.apiKey.trimmingCharacters(in: .whitespaces)
        if trimmedKey.isEmpty {
            try? KeychainHelper.delete(service: keychainService, account: keychainAccount(for: provider))
        } else {
            try? KeychainHelper.save(service: keychainService, account: keychainAccount(for: provider), data: config.apiKey)
        }
        defaults.set(config.baseURL, forKey: overrideBaseURLKey(provider))
        defaults.set(config.model, forKey: overrideModelKey(provider))
    }

    private func keychainAccount(for provider: AIProvider) -> String {
        "api-key.\(provider.rawValue)"
    }

    private func overrideBaseURLKey(_ provider: AIProvider) -> String {
        "provider.\(provider.rawValue).baseURL"
    }

    private func overrideModelKey(_ provider: AIProvider) -> String {
        "provider.\(provider.rawValue).model"
    }

    private func migrateLegacyIfNeeded() {
        guard defaults.string(forKey: activeProviderKey) == nil else { return }
        guard let legacyRaw = defaults.string(forKey: legacyProviderKey) else { return }

        let legacyMap: [String: AIProvider] = [
            "OpenAI": .openai,
            "智谱 GLM": .zhipu,
            "DeepSeek": .deepseek,
            "月之暗面": .kimi,
            "自定义": .custom,
        ]
        guard let provider = legacyMap[legacyRaw] else { return }

        let legacyKey = (try? KeychainHelper.load(service: keychainService, account: legacyKeychainAccount)) ?? ""
        if !legacyKey.isEmpty {
            try? KeychainHelper.save(service: keychainService, account: keychainAccount(for: provider), data: legacyKey)
            try? KeychainHelper.delete(service: keychainService, account: legacyKeychainAccount)
        }

        if provider == .custom {
            if let url = defaults.string(forKey: legacyCustomBaseURLKey), !url.isEmpty {
                defaults.set(url, forKey: overrideBaseURLKey(.custom))
            }
            if let model = defaults.string(forKey: legacyCustomModelKey), !model.isEmpty {
                defaults.set(model, forKey: overrideModelKey(.custom))
            }
        }

        defaults.set(provider.rawValue, forKey: activeProviderKey)
        defaults.removeObject(forKey: legacyProviderKey)
        defaults.removeObject(forKey: legacyCustomBaseURLKey)
        defaults.removeObject(forKey: legacyCustomModelKey)
    }
}
