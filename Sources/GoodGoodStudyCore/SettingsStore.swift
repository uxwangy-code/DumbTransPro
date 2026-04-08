import Foundation

private let keychainService = "com.whimsycode.good-good-study"
private let keychainAccount = "openai-api-key"

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var apiKey: String = ""

    public init() {
        loadAPIKey()
    }

    public func loadAPIKey() {
        apiKey = (try? KeychainHelper.load(service: keychainService, account: keychainAccount)) ?? ""
    }

    public func saveAPIKey() {
        if apiKey.isEmpty {
            try? KeychainHelper.delete(service: keychainService, account: keychainAccount)
        } else {
            try? KeychainHelper.save(service: keychainService, account: keychainAccount, data: apiKey)
        }
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
