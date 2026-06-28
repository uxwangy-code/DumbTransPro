import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
struct SettingsStoreUsageTelemetryTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.usage-telemetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func anonymousUsageDataSharingDefaultsOnAndRespectsUserChoice() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.shareAnonymousUsageData)
        #expect(SettingsStore(defaults: defaults).shareAnonymousUsageData)

        store.setShareAnonymousUsageData(false)
        #expect(!store.shareAnonymousUsageData)
        #expect(!SettingsStore(defaults: defaults).shareAnonymousUsageData)

        store.setShareAnonymousUsageData(true)
        #expect(store.shareAnonymousUsageData)
        #expect(SettingsStore(defaults: defaults).shareAnonymousUsageData)
    }
}

@Suite(.serialized)
struct UsageTelemetryTests {
    private func makeTestSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TelemetryURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func payloadJSON() throws -> [String: Any] {
        let data = try #require(TelemetryURLProtocol.lastRequestBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func disabledOrMissingEndpointDoesNotSend() async throws {
        TelemetryURLProtocol.reset()
        let event = UsageTelemetryEvent.appLaunched(licenseTier: .free)
        let context = UsageTelemetryContext(appVersion: "1.4.0 (120)", macOSVersion: "macOS 15.5")

        let disabledClient = UsageTelemetryClient(
            endpoint: URL(string: "https://example.com/events")!,
            session: makeTestSession(),
            context: context,
            now: { Date(timeIntervalSince1970: 0) }
        )
        await disabledClient.send(event, isEnabled: false)

        let noEndpointClient = UsageTelemetryClient(
            endpoint: nil,
            session: makeTestSession(),
            context: context,
            now: { Date(timeIntervalSince1970: 0) }
        )
        await noEndpointClient.send(event, isEnabled: true)

        #expect(TelemetryURLProtocol.allRequestBodies.isEmpty)
    }

    @Test func enabledClientSendsOnlyAnonymousProductMetadata() async throws {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockResponseData = Data("{}".utf8)
        TelemetryURLProtocol.mockStatusCode = 202

        let client = UsageTelemetryClient(
            endpoint: URL(string: "https://example.com/events")!,
            session: makeTestSession(),
            context: UsageTelemetryContext(appVersion: "1.4.0 (120)", macOSVersion: "macOS 15.5"),
            now: { Date(timeIntervalSince1970: 0) }
        )

        await client.send(
            .translationSucceeded(
                action: .rewrite,
                route: .ai,
                provider: .openai,
                direction: .chineseToEnglish,
                style: .natural,
                licenseTier: .free
            ),
            isEnabled: true
        )

        let payload = try payloadJSON()
        #expect(payload["schemaVersion"] as? Int == 1)
        #expect(payload["sentAt"] as? String == "1970-01-01T00:00:00Z")

        let context = try #require(payload["context"] as? [String: Any])
        #expect(context["appVersion"] as? String == "1.4.0 (120)")
        #expect(context["macOSVersion"] as? String == "macOS 15.5")

        let event = try #require(payload["event"] as? [String: Any])
        #expect(event["name"] as? String == "translation_succeeded")
        #expect(event["action"] as? String == "rewrite")
        #expect(event["route"] as? String == "ai")
        #expect(event["provider"] as? String == "openai")
        #expect(event["direction"] as? String == "chinese_to_english")
        #expect(event["style"] as? String == "natural")
        #expect(event["licenseTier"] as? String == "free")

        let body = String(data: try #require(TelemetryURLProtocol.lastRequestBody), encoding: .utf8) ?? ""
        #expect(!body.contains("好好学习"))
        #expect(!body.contains("study-hard"))
        #expect(!body.contains("sk-test"))
        #expect(!body.contains("license-key"))
        #expect(!body.localizedCaseInsensitiveContains("clipboard"))
    }

    @Test func appLaunchPayloadIncludesOnlyVersionAndTier() async throws {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockResponseData = Data("{}".utf8)
        TelemetryURLProtocol.mockStatusCode = 202

        let client = UsageTelemetryClient(
            endpoint: URL(string: "https://example.com/events")!,
            session: makeTestSession(),
            context: UsageTelemetryContext(appVersion: "1.4.0 (120)", macOSVersion: "macOS 15.5"),
            now: { Date(timeIntervalSince1970: 0) }
        )

        await client.send(.appLaunched(licenseTier: .pro), isEnabled: true)

        let payload = try payloadJSON()
        let context = try #require(payload["context"] as? [String: Any])
        #expect(context["appVersion"] as? String == "1.4.0 (120)")
        #expect(context["macOSVersion"] as? String == "macOS 15.5")

        let event = try #require(payload["event"] as? [String: Any])
        #expect(event["name"] as? String == "app_launched")
        #expect(event["licenseTier"] as? String == "pro")

        let body = String(data: try #require(TelemetryURLProtocol.lastRequestBody), encoding: .utf8) ?? ""
        #expect(!body.contains("apiKey"))
        #expect(!body.contains("licenseKey"))
        #expect(!body.localizedCaseInsensitiveContains("clipboard"))
    }

    @Test func providerValuesAvoidInternalOrEndpointDetails() {
        #expect(UsageTelemetryProvider(provider: .openai) == .openai)
        #expect(UsageTelemetryProvider(provider: .custom) == .custom)
        #expect(UsageTelemetryProvider(provider: .friday) == .custom)
    }

    @Test func errorKindsAreCoarseAndDoNotExposeMessages() {
        #expect(UsageTelemetryErrorKind(error: TranslateError.requestTimedOut) == .timeout)
        #expect(UsageTelemetryErrorKind(error: TranslateError.contentBlocked(message: "secret text")) == .contentBlocked)
        #expect(UsageTelemetryErrorKind(error: TranslateError.apiError(statusCode: 401, message: "sk-test leaked")) == .apiError)
        #expect(UsageTelemetryErrorKind(error: TranslateError.networkError(URLError(.notConnectedToInternet))) == .network)
        #expect(UsageTelemetryErrorKind(error: TranslateError.invalidResponse) == .invalidResponse)
        #expect(UsageTelemetryErrorKind(error: NSError(domain: "Local", code: 9)) == .unknown)
    }
}

final class TelemetryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 202
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var allRequestBodies: [Data] = []

    static func reset() {
        mockResponseData = nil
        mockStatusCode = 202
        lastRequestBody = nil
        allRequestBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBodyStream(from: request)
        Self.lastRequestBody = body
        if let body { Self.allRequestBodies.append(body) }

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
