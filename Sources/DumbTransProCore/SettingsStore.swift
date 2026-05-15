import Foundation

private let keychainService = "com.whimsycode.dumbtrans-pro"
private let keychainAccount = "api-key"

public enum AIProvider: String, CaseIterable, Sendable {
    case openai = "OpenAI"
    case zhipu = "智谱 GLM"
    case deepseek = "DeepSeek"
    case moonshot = "月之暗面"
    case custom = "自定义"

    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .custom: return ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .zhipu: return "glm-4-flash"
        case .deepseek: return "deepseek-chat"
        case .moonshot: return "moonshot-v1-8k"
        case .custom: return ""
        }
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var apiKey: String = ""
    @Published public var provider: AIProvider = .openai
    @Published public var customBaseURL: String = ""
    @Published public var customModel: String = ""
    @Published public var translationStyle: TranslationStyle = .natural

    public init() {
        loadSettings()
    }

    public func loadSettings() {
        apiKey = (try? KeychainHelper.load(service: keychainService, account: keychainAccount)) ?? ""
        if let raw = UserDefaults.standard.string(forKey: "provider"),
           let p = AIProvider(rawValue: raw) {
            provider = p
        }
        customBaseURL = UserDefaults.standard.string(forKey: "customBaseURL") ?? ""
        customModel = UserDefaults.standard.string(forKey: "customModel") ?? ""
        if let raw = UserDefaults.standard.string(forKey: "translationStyle"),
           let style = TranslationStyle(rawValue: raw) {
            translationStyle = style
        } else {
            translationStyle = .natural
        }
    }

    public func saveSettings() {
        // API Key
        if apiKey.isEmpty {
            try? KeychainHelper.delete(service: keychainService, account: keychainAccount)
        } else {
            try? KeychainHelper.save(service: keychainService, account: keychainAccount, data: apiKey)
        }
        // Provider settings
        UserDefaults.standard.set(provider.rawValue, forKey: "provider")
        UserDefaults.standard.set(customBaseURL, forKey: "customBaseURL")
        UserDefaults.standard.set(customModel, forKey: "customModel")
        UserDefaults.standard.set(translationStyle.rawValue, forKey: "translationStyle")
    }

    public func updateSettings(
        apiKey: String,
        provider: AIProvider,
        customBaseURL: String,
        customModel: String,
        translationStyle: TranslationStyle
    ) {
        self.apiKey = apiKey
        self.provider = provider
        self.customBaseURL = customBaseURL
        self.customModel = customModel
        self.translationStyle = translationStyle
        saveSettings()
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var baseURL: String {
        if provider == .custom {
            return customBaseURL
        }
        return provider.defaultBaseURL
    }

    public var model: String {
        if provider == .custom {
            return customModel
        }
        return provider.defaultModel
    }
}
