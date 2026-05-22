import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
@Suite(.serialized)
struct SettingsStoreAPIKeyTests {
    private let apiKeysAccount = "api-keys"

    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.api-keys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func freshService() -> String {
        "com.whimsycode.dumbtrans-pro.test.api-keys.\(UUID().uuidString)"
    }

    private func deleteItems(service: String, accounts: [String]) {
        for account in accounts {
            try? KeychainHelper.delete(service: service, account: account)
        }
    }

    private func loadStoredKeys(service: String) throws -> [String: String] {
        let stored = try KeychainHelper.load(service: service, account: apiKeysAccount)
        let raw = try #require(stored)
        let data = try #require(raw.data(using: .utf8))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    @Test func providerKeysPersistInSingleKeychainItem() throws {
        let service = freshService()
        defer {
            deleteItems(service: service, accounts: [apiKeysAccount, "api-key.friday", "api-key.zhipu"])
        }

        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults, keychainService: service)
        store.updateConfig(.friday, ProviderConfig(apiKey: "friday-key"))
        store.updateConfig(.zhipu, ProviderConfig(apiKey: "zhipu-key"))

        let storedKeys = try loadStoredKeys(service: service)
        #expect(storedKeys == ["friday": "friday-key", "zhipu": "zhipu-key"])
        #expect(try KeychainHelper.load(service: service, account: "api-key.friday") == nil)
        #expect(try KeychainHelper.load(service: service, account: "api-key.zhipu") == nil)

        let reloaded = SettingsStore(defaults: defaults, keychainService: service)
        #expect(reloaded.config(for: .friday).apiKey == "friday-key")
        #expect(reloaded.config(for: .zhipu).apiKey == "zhipu-key")
    }

    @Test func legacyProviderKeyMigratesOnlyWhenProviderIsAccessed() throws {
        let service = freshService()
        defer {
            deleteItems(service: service, accounts: [apiKeysAccount, "api-key.friday", "api-key.zhipu"])
        }

        try KeychainHelper.save(service: service, account: "api-key.friday", data: "friday-key")
        try KeychainHelper.save(service: service, account: "api-key.zhipu", data: "zhipu-key")

        let store = SettingsStore(defaults: freshDefaults(), keychainService: service)
        #expect(try KeychainHelper.load(service: service, account: apiKeysAccount) == nil)

        #expect(store.config(for: .friday).apiKey == "friday-key")
        #expect(try loadStoredKeys(service: service) == ["friday": "friday-key"])
        #expect(try KeychainHelper.load(service: service, account: "api-key.friday") == nil)
        #expect(try KeychainHelper.load(service: service, account: "api-key.zhipu") == "zhipu-key")
    }
}
