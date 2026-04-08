import Foundation
import Testing
@testable import GoodGoodStudyCore

@Suite(.serialized)
struct KeychainHelperTests {
    private let testService = "com.whimsycode.good-good-study.test"
    private let testAccount = "api-key-test"

    @Test func saveAndRetrieve() throws {
        // Clean up any leftover from previous test runs
        try? KeychainHelper.delete(service: testService, account: testAccount)
        let key = "sk-test-\(UUID().uuidString.prefix(8))"
        try KeychainHelper.save(service: testService, account: testAccount, data: key)
        let retrieved = try KeychainHelper.load(service: testService, account: testAccount)
        #expect(retrieved == key)
        try KeychainHelper.delete(service: testService, account: testAccount)
    }

    @Test func loadNonExistent() {
        let result = try? KeychainHelper.load(service: testService, account: "nonexistent-\(UUID())")
        #expect(result == nil)
    }

    @Test func overwrite() throws {
        // Clean up any leftover from previous test runs
        try? KeychainHelper.delete(service: testService, account: testAccount)
        let key1 = "sk-first"
        let key2 = "sk-second"
        try KeychainHelper.save(service: testService, account: testAccount, data: key1)
        try KeychainHelper.save(service: testService, account: testAccount, data: key2)
        let retrieved = try KeychainHelper.load(service: testService, account: testAccount)
        #expect(retrieved == key2)
        try KeychainHelper.delete(service: testService, account: testAccount)
    }
}
