import Foundation
import Testing
@testable import DumbTransProCore

private struct MockVerifier: LicenseVerifying {
    enum Behavior {
        case valid
        case invalid(String)
        case networkError
        case gatewayServerError
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
        case .gatewayServerError:
            throw LicenseError.network("HTTP 500")
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

    @Test func offlineAfterRecentVerificationKeepsPro() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let defaults = freshDefaults()
        let clock = Clock()
        let activated = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        try await activated.activate(key: "KEY")

        // 几天后断网重启：只要本机曾成功验证过，联网失败不应让用户掉回免费版
        clock.advance(days: 2)
        let offline = makeManager(defaults: defaults, service: service, behavior: .networkError, clock: clock)
        #expect(offline.tier == .pro)
        await offline.revalidateIfNeeded()
        #expect(offline.tier == .pro)
    }

    @Test func offlineBeyondGraceKeepsProAndSurfacesRetryGuidance() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let defaults = freshDefaults()
        let clock = Clock()
        let activated = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        try await activated.activate(key: "KEY")

        clock.advance(days: 15)
        let offline = makeManager(defaults: defaults, service: service, behavior: .networkError, clock: clock)
        #expect(offline.tier == .pro)
        await offline.revalidateIfNeeded()
        #expect(offline.tier == .pro)
        if case .network(let reason) = offline.lastVerificationProblem {
            #expect(reason.contains("offline"))
        } else {
            Issue.record("Expected network verification problem")
        }
        #expect(offline.proStatusDetail?.contains("可尝试挂🪜") == true)
        #expect(try KeychainHelper.load(service: service, account: licenseAccount) == "KEY")

        let backOnline = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        await backOnline.revalidateIfNeeded()
        #expect(backOnline.tier == .pro)
        #expect(backOnline.lastVerificationProblem == nil)
    }

    @Test func gatewayServerErrorDuringRevalidationKeepsProAndKey() async throws {
        let service = freshService()
        defer { try? KeychainHelper.delete(service: service, account: licenseAccount) }

        let defaults = freshDefaults()
        let clock = Clock()
        let activated = makeManager(defaults: defaults, service: service, behavior: .valid, clock: clock)
        try await activated.activate(key: "DTP-KEY-123")

        clock.advance(days: Double(LicenseManager.revalidationIntervalDays) + 1)
        let serverError = makeManager(defaults: defaults, service: service, behavior: .gatewayServerError, clock: clock)
        await serverError.revalidateIfNeeded()

        #expect(serverError.tier == .pro)
        if case .network(let reason) = serverError.lastVerificationProblem {
            #expect(reason.contains("HTTP 500"))
        } else {
            Issue.record("Expected server error to surface as network verification problem")
        }
        #expect(try KeychainHelper.load(service: service, account: licenseAccount) == "DTP-KEY-123")
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

    @Test func compositeVerifierFallsBackFromNewChannelToLegacyChannel() async throws {
        let verifier = CompositeLicenseVerifier(verifiers: [
            MockVerifier(behavior: .invalid("not found")),
            MockVerifier(behavior: .valid),
        ])

        let result = try await verifier.verify(key: "LEGACY-GUMROAD-KEY", incrementUses: false)

        #expect(result.isValid)
    }
}

@Suite(.serialized)
struct LicenseGatewayVerifierTests {
    private func makeTestSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func activationPostsJSONBodyToConfiguredEndpoint() async throws {
        LicenseURLProtocol.reset()
        LicenseURLProtocol.mockResponseData = Data("""
        {
          "valid": true
        }
        """.utf8)

        let verifier = LicenseGatewayVerifier(
            session: makeTestSession(),
            verifyURL: URL(string: "https://license.example.com/api/licenses/verify")!
        )

        let result = try await verifier.verify(key: "DTP-KEY-123", incrementUses: true)

        #expect(result.isValid)
        #expect(LicenseURLProtocol.lastRequest?.url?.absoluteString == "https://license.example.com/api/licenses/verify")
        #expect(LicenseURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = String(data: try #require(LicenseURLProtocol.lastRequestBody), encoding: .utf8) ?? ""
        #expect(body.contains("\"license_key\":\"DTP-KEY-123\""))
        #expect(body.contains("\"increment_uses\":true"))
        #expect(body.contains("\"app\":\"DumbTransPro\""))
    }

    @Test func validationRejectsInvalidGatewayResponse() async throws {
        LicenseURLProtocol.reset()
        LicenseURLProtocol.mockResponseData = Data("""
        {
          "valid": false,
          "reason": "refunded"
        }
        """.utf8)

        let verifier = LicenseGatewayVerifier(
            session: makeTestSession(),
            verifyURL: URL(string: "https://license.example.com/api/licenses/verify")!
        )

        let result = try await verifier.verify(key: "REFUNDED-KEY", incrementUses: false)

        #expect(!result.isValid)
        #expect(result.failureReason == "refunded")
    }

    @Test func serverErrorThrowsNetworkInsteadOfInvalidatingLicense() async {
        LicenseURLProtocol.reset()
        LicenseURLProtocol.mockStatusCode = 500
        LicenseURLProtocol.mockResponseData = Data("""
        {
          "error": "service_unavailable"
        }
        """.utf8)

        let verifier = LicenseGatewayVerifier(
            session: makeTestSession(),
            verifyURL: URL(string: "https://license.example.com/api/licenses/verify")!
        )

        await #expect(throws: LicenseError.network("HTTP 500")) {
            _ = try await verifier.verify(key: "DTP-KEY-123", incrementUses: false)
        }
    }
}

final class LicenseURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset() {
        mockResponseData = nil
        mockStatusCode = 200
        lastRequest = nil
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readBodyStream(from: request)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let payload = Self.mockResponseData {
            client?.urlProtocol(self, didLoad: payload)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}
