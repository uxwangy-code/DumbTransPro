import Foundation
import Testing
@testable import DumbTransProCore

private struct MockVerifier: LicenseVerifying {
    enum Behavior {
        case valid
        case invalid(String)
        case networkError
    }

    let behavior: Behavior

    func verify(key: String, incrementUses: Bool) async throws -> LicenseVerification {
        switch behavior {
        case .valid:
            return LicenseVerification(isValid: true)
        case .invalid(let reason):
            return LicenseVerification(isValid: false, failureReason: reason)
        case .networkError:
            throw LicenseError.network("offline")
        }
    }
}

/// 可拨动的时钟，模拟跨天 / 跨宽限期
private final class Clock: @unchecked Sendable {
    var current: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_750_000_000)) { current = date }
    func advance(days: Double) { current = current.addingTimeInterval(days * 86400) }
}

@MainActor
@Suite(.serialized)
struct LicenseManagerTests {
    private let licenseAccount = "license-key"

    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.license.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func freshService() -> String {
        "com.whimsycode.dumbtrans-pro.test.license.\(UUID().uuidString)"
    }

    private func makeManager(
        defaults: UserDefaults,
        service: String,
        behavior: MockVerifier.Behavior,
        clock: Clock = Clock()
    ) -> LicenseManager {
        LicenseManager(
            defaults: defaults,
            keychainService: service,
            verifier: MockVerifier(behavior: behavior),
            now: { clock.current }
        )
    }

    @Test func activateValidKeyUnlocksPro() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .valid)
        #expect(manager.tier == .free)

        try await manager.activate(key: "GUMROAD-KEY-1234")
        #expect(manager.tier == .pro)
        #expect(manager.gate(provider: .deepseek) == .allowed)
        #expect(try KeychainHelper.load(service: service, account: licenseAccount) == "GUMROAD-KEY-1234")
    }

    @Test func activateInvalidKeyStaysFree() async {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .invalid("refunded"))
        await #expect(throws: LicenseError.invalidKey("refunded")) {
            try await manager.activate(key: "BAD-KEY")
        }
        #expect(manager.tier == .free)
    }

    @Test func activateEmptyKeyThrows() async {
        let service = freshService()
        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .valid)
        await #expect(throws: LicenseError.emptyKey) {
            try await manager.activate(key: "   ")
        }
    }

    @Test func freeTierLocksNonFreeProviders() {
        let service = freshService()
        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .valid)

        #expect(manager.gate(provider: .openai) == .allowed)
        #expect(manager.gate(provider: .zhipu) == .allowed)
        #expect(manager.gate(provider: .deepseek) == .providerLocked(.deepseek))
        #expect(manager.gate(provider: .custom) == .providerLocked(.custom))
    }

    @Test func freeTierHitsDailyLimitAndResetsNextDay() {
        let service = freshService()
        let clock = Clock()
        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .valid, clock: clock)

        for _ in 0..<LicenseManager.freeDailyLimit {
            #expect(manager.gate(provider: .openai) == .allowed)
            manager.recordTranslation()
        }
        #expect(manager.gate(provider: .openai) == .dailyLimitReached(limit: LicenseManager.freeDailyLimit))
        #expect(manager.remainingToday == 0)

        clock.advance(days: 1)
        #expect(manager.gate(provider: .openai) == .allowed)
        #expect(manager.remainingToday == LicenseManager.freeDailyLimit)
    }

    @Test func proDoesNotConsumeQuota() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .valid)
        try await manager.activate(key: "KEY")
        manager.recordTranslation()
        #expect(manager.remainingToday == LicenseManager.freeDailyLimit)
    }

    @Test func offlineWithinGraceKeepsPro() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let defaults = freshDefaults()
        let clock = Clock()
        let activated = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        try await activated.activate(key: "KEY")

        // 几天后断网重启：宽限期内仍是 Pro
        clock.advance(days: Double(LicenseManager.offlineGraceDays) - 1)
        let offline = makeManager(defaults: defaults, service: service, behavior: .networkError, clock: clock)
        #expect(offline.tier == .pro)
        await offline.revalidateIfNeeded()
        #expect(offline.tier == .pro)
    }

    @Test func offlineBeyondGraceDegradesButKeepsKey() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let defaults = freshDefaults()
        let clock = Clock()
        let activated = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        try await activated.activate(key: "KEY")

        clock.advance(days: Double(LicenseManager.offlineGraceDays) + 1)
        let offline = makeManager(defaults: defaults, service: service, behavior: .networkError, clock: clock)
        #expect(offline.tier == .free)
        // key 没被摘除，网络恢复后复验可回到 Pro
        #expect(try KeychainHelper.load(service: service, account: licenseAccount) == "KEY")

        let backOnline = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        await backOnline.revalidateIfNeeded()
        #expect(backOnline.tier == .pro)
    }

    @Test func revalidateRemovesExplicitlyInvalidKey() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let defaults = freshDefaults()
        let clock = Clock()
        let activated = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        try await activated.activate(key: "KEY")

        clock.advance(days: Double(LicenseManager.revalidationIntervalDays) + 1)
        let refunded = makeManager(defaults: defaults, service: service, behavior: .invalid("订单已退款"), clock: clock)
        await refunded.revalidateIfNeeded()
        #expect(refunded.tier == .free)
        #expect(try KeychainHelper.load(service: service, account: licenseAccount) == nil)
    }

    @Test func deactivateRemovesKeyAndDowngrades() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let manager = makeManager(defaults: freshDefaults(), service: service, behavior: .valid)
        try await manager.activate(key: "KEY")
        manager.deactivate()
        #expect(manager.tier == .free)
        #expect(try KeychainHelper.load(service: service, account: licenseAccount) == nil)
    }
}
