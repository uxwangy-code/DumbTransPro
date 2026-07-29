import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
struct SettingsStoreProviderConfigTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.provider-config.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func freshService() -> String {
        "com.whimsycode.dumbtrans-pro.test.provider-config.\(UUID().uuidString)"
    }

    @Test func endpointPolicyAllowsManualEndpointOnlyForCustomProvider() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults, keychainService: freshService())

        let zhipuCodingEndpoint = "https://open.bigmodel.cn/api/coding/paas/v4"
        store.updateConfig(.zhipu, ProviderConfig(baseURL: zhipuCodingEndpoint))
        #expect(store.config(for: .zhipu).baseURL == zhipuCodingEndpoint)

        store.updateConfig(.zhipu, ProviderConfig(baseURL: "https://example.com/openai-compatible/v1"))
        #expect(store.config(for: .zhipu).baseURL == "")

        store.updateConfig(.custom, ProviderConfig(baseURL: "https://example.com/openai-compatible/v1"))
        #expect(store.config(for: .custom).baseURL == "https://example.com/openai-compatible/v1")
    }

    @Test func translationEnginePreferenceIsOptionalAndPersists() {
        let defaults = freshDefaults()
        let service = freshService()
        let initial = SettingsStore(defaults: defaults, keychainService: service)

        #expect(initial.preferredTranslationEngine == nil)

        initial.setPreferredTranslationEngine(.offline)

        let reloaded = SettingsStore(defaults: defaults, keychainService: service)
        #expect(reloaded.preferredTranslationEngine == .offline)
    }
}
