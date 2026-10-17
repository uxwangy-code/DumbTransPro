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
        let store = SettingsStore(defaults: defaults, keychainService: "test.no-keys.\(UUID())")

        #expect(store.shareAnonymousUsageData)
        #expect(SettingsStore(defaults: defaults, keychainService: "test.no-keys.\(UUID())").shareAnonymousUsageData)

        store.setShareAnonymousUsageData(false)
        #expect(!store.shareAnonymousUsageData)
        #expect(!SettingsStore(defaults: defaults, keychainService: "test.no-keys.\(UUID())").shareAnonymousUsageData)

        store.setShareAnonymousUsageData(true)
        #expect(store.shareAnonymousUsageData)
        #expect(SettingsStore(defaults: defaults, keychainService: "test.no-keys.\(UUID())").shareAnonymousUsageData)
    }
}

@MainActor
@Suite(.serialized)
struct UsageTelemetryTests {
    private func makeClient(queue: TelemetryEventQueue = TelemetryEventQueue(storageURL: nil), retryDelayNanoseconds: UInt64 = 0,
                            retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) -> UsageTelemetryClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TelemetryURLProtocol.self]
        let defaults = UserDefaults(suiteName: "telemetry-network.\(UUID())")!
        return UsageTelemetryClient(endpoint: URL(string: "http://127.0.0.1:18698/events")!,
            session: URLSession(configuration: config),
            context: UsageTelemetryContext(appVersion: "1.5.5 (155)", macOSVersion: "macOS 15.5", buildChannel: .development),
            consentStore: TelemetryConsentStore(defaults: defaults), identityStore: MemoryTelemetryIdentityStore(), queue: queue,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }, retryDelayNanoseconds: retryDelayNanoseconds, observeNetworkChanges: false, retrySleep: retrySleep)
    }

    @Test func developmentBuildNeverUploadsToProduction() async {
        TelemetryURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TelemetryURLProtocol.self]
        let defaults = UserDefaults(suiteName: "telemetry-dev-isolation.\(UUID())")!
        let client = UsageTelemetryClient(endpoint: URL(string: "https://telemetry.whimsycode.com/events"),
            session: URLSession(configuration: config),
            context: UsageTelemetryContext(appVersion: "test", macOSVersion: "macOS", buildChannel: .development),
            consentStore: TelemetryConsentStore(defaults: defaults), identityStore: MemoryTelemetryIdentityStore(),
            queue: TelemetryEventQueue(storageURL: nil), observeNetworkChanges: false)
        client.setConsent(true)
        await client.flush()
        #expect(TelemetryURLProtocol.allRequests.isEmpty)
    }

    @Test func productionClientDropsPersistedDevelopmentPayloadBeforeSending() async throws {
        TelemetryURLProtocol.reset()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("telemetry-cross-channel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.json")
        let developmentQueue = TelemetryEventQueue(storageURL: url)
        let devDefaults = UserDefaults(suiteName: "telemetry-dev-queue.\(UUID())")!
        let development = UsageTelemetryClient(endpoint: nil,
            context: UsageTelemetryContext(appVersion: "dev", macOSVersion: "macOS", buildChannel: .development),
            consentStore: TelemetryConsentStore(defaults: devDefaults), identityStore: MemoryTelemetryIdentityStore(),
            queue: developmentQueue)
        development.setConsent(true)
        let request = development.beginTranslation(action: .lookup, licenseTier: .free)
        development.finishTranslation(request, outcome: .succeeded, route: .offline, delivery: .panelShown)
        #expect(developmentQueue.entries.count == 3)
        let restored = TelemetryEventQueue(storageURL: url)
        let productionDefaults = UserDefaults(suiteName: "telemetry-prod-queue.\(UUID())")!
        let productionConsent = TelemetryConsentStore(defaults: productionDefaults, buildChannel: .production)
        productionConsent.setAllowed(true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TelemetryURLProtocol.self]
        let production = UsageTelemetryClient(endpoint: URL(string: "https://telemetry.whimsycode.com/events"),
            session: URLSession(configuration: config),
            context: UsageTelemetryContext(appVersion: "production", macOSVersion: "macOS", buildChannel: .production),
            consentStore: productionConsent, identityStore: MemoryTelemetryIdentityStore(),
            queue: restored, observeNetworkChanges: false)
        await production.flush()
        #expect(TelemetryURLProtocol.allRequestBodies.isEmpty)
        #expect(restored.entries.isEmpty)
    }

    @Test func networkRecoveryWakesBackoffUsingIdenticalBody() async throws {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockErrors = [URLError(.notConnectedToInternet)]
        let sleeping = TelemetryTestSignal()
        let secondRequest = TelemetryTestSignal()
        TelemetryURLProtocol.onRequest = { count in if count == 2 { secondRequest.signal() } }
        let client = makeClient(retryDelayNanoseconds: 30_000_000_000, retrySleep: { nanoseconds in
            sleeping.signal()
            try await Task.sleep(nanoseconds: nanoseconds)
        })
        defer { client.setConsent(false) }
        client.setConsent(true)
        // This signal comes from the actual injected sleeper, after retryWait
        // has been installed. Exactly one recovery notification follows it.
        let enteredBackoff = await sleeping.wait()
        try #require(enteredBackoff)
        #expect(TelemetryURLProtocol.allRequests.count == 1)
        client.networkDidBecomeAvailable()
        let resumed = await secondRequest.wait()
        #expect(resumed)
        #expect(TelemetryURLProtocol.allRequests.count == 2)
        #expect(TelemetryURLProtocol.allRequestBodies.first == TelemetryURLProtocol.allRequestBodies.last)
        if resumed { await client.flush() }
    }

    @Test func oneRecoveryWhileFailureIsInFlightSkipsTheNextLocalBackoff() async throws {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockErrors = [URLError(.notConnectedToInternet)]
        let failureGate = TelemetryFailureGate()
        let secondRequest = TelemetryTestSignal()
        TelemetryURLProtocol.firstFailureGate = failureGate
        TelemetryURLProtocol.onRequest = { count in
            if count == 2 {
                failureGate.recordSecondAttempt()
                secondRequest.signal()
            }
        }
        let client = makeClient(retryDelayNanoseconds: 30_000_000_000)
        defer { client.setConsent(false) }
        client.setConsent(true)
        let requestHeld = await failureGate.held.wait()
        try #require(requestHeld)
        client.networkDidBecomeAvailable() // the only recovery notification
        #expect(TelemetryURLProtocol.allRequests.count == 1)
        failureGate.release() // the old in-flight operation reports its failure later
        let resumed = await secondRequest.wait()
        #expect(resumed)
        #expect(TelemetryURLProtocol.allRequests.count == 2)
        #expect(!failureGate.secondAttemptOverlapped)
        #expect(TelemetryURLProtocol.allRequestBodies.first == TelemetryURLProtocol.allRequestBodies.last)
        if resumed { await client.flush() }
    }

    @Test func recoveryDoesNotReplaceInFlightRequestAndOptOutStillClears() async throws {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockResponseDelay = 0.1
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = makeClient(queue: queue, retryDelayNanoseconds: 30_000_000_000)
        client.setConsent(true)
        for _ in 0..<100 where TelemetryURLProtocol.allRequests.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        client.networkDidBecomeAvailable()
        try await Task.sleep(for: .milliseconds(15))
        #expect(TelemetryURLProtocol.allRequests.count == 1)
        client.setConsent(false)
        client.networkDidBecomeAvailable()
        try await Task.sleep(for: .milliseconds(120))
        #expect(TelemetryURLProtocol.allRequests.count == 1)
        #expect(queue.entries.isEmpty)
    }

    @Test func legacyEnabledFlagCannotAuthorizeV3() async {
        TelemetryURLProtocol.reset()
        let client = makeClient()
        client.record(.appLaunched(licenseTier: .free), isEnabled: true)
        await client.flush()
        #expect(TelemetryURLProtocol.allRequestBodies.isEmpty)
        #expect(client.installationID == nil)
    }

    @Test func payloadOnlyCarriesAllowedV3MetadataAndLifecycleFields() async throws {
        TelemetryURLProtocol.reset()
        let client = makeClient()
        client.setConsent(true)
        let request = client.beginTranslation(action: .rewrite, licenseTier: .free)
        client.finishTranslation(request, outcome: .succeeded, route: .ai, provider: .openai,
                                 direction: .chineseToEnglish, style: .natural, delivery: .pasteRequested)
        await client.flush()
        let data = try #require(TelemetryURLProtocol.lastRequestBody)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == ["schemaVersion", "eventId", "installationId", "occurredAt", "policyVersion", "collectionMode", "context", "event"])
        #expect(payload["schemaVersion"] as? Int == 3)
        #expect(payload["occurredAt"] as? String == "2023-11-14T22:13:20.000Z")
        let context = try #require(payload["context"] as? [String: Any])
        #expect(Set(context.keys) == ["appVersion", "macOSVersion", "buildChannel"])
        #expect(context["buildChannel"] as? String == "development")
        let event = try #require(payload["event"] as? [String: Any])
        #expect(event["name"] as? String == "translation_succeeded")
        #expect(event["requestId"] as? String == request?.requestId)
        #expect(event["delivery"] as? String == "paste_requested")
        #expect(event["failureStage"] == nil)
    }

    @Test func transientFailureRetriesTheExactPayloadAndThenDeletesIt() async {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockErrors = [URLError(.timedOut)]
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = makeClient(queue: queue)
        client.setConsent(true)
        await client.flush()
        #expect(TelemetryURLProtocol.allRequests.count == 2)
        #expect(TelemetryURLProtocol.allRequestBodies.first == TelemetryURLProtocol.allRequestBodies.last)
        #expect(TelemetryURLProtocol.allRequests.allSatisfy { $0.timeoutInterval == 15 })
        #expect(queue.entries.isEmpty)
    }

    @Test func temporaryHTTPStatusesRetryAnd409IsPermanentlyRemoved() async {
        for status in [408, 429, 500, 503] {
            TelemetryURLProtocol.reset()
            TelemetryURLProtocol.mockStatusCodes = [status, 202]
            let queue = TelemetryEventQueue(storageURL: nil)
            let client = makeClient(queue: queue)
            client.setConsent(true)
            await client.flush()
            #expect(TelemetryURLProtocol.allRequests.count == 2)
            #expect(TelemetryURLProtocol.allRequestBodies.first == TelemetryURLProtocol.allRequestBodies.last)
            #expect(queue.entries.isEmpty)
        }
        for status in [400, 409] {
            TelemetryURLProtocol.reset()
            TelemetryURLProtocol.mockStatusCode = status
            let queue = TelemetryEventQueue(storageURL: nil)
            let client = makeClient(queue: queue)
            client.setConsent(true)
            await client.flush()
            #expect(queue.entries.isEmpty)
            #expect(queue.diagnostics.rejectedPermanent == 1)
            #expect(TelemetryURLProtocol.allRequests.count == 2)
        }
    }

    @Test func healthContainsCumulativeCountersAndNoActivityDimensions() async throws {
        TelemetryURLProtocol.reset()
        let queue = TelemetryEventQueue(storageURL: nil, maxCount: 1)
        let client = makeClient(queue: queue)
        client.setConsent(true)
        client.recordAppLaunched(licenseTier: .free)
        await client.flush()
        let bodies = try TelemetryURLProtocol.allRequestBodies.map { try JSONDecoder().decode(UsageTelemetryPayload.self, from: $0) }
        let health = try #require(bodies.first { $0.event.name == .telemetryHealth })
        #expect(health.event.droppedOverflow! >= 1)
        #expect(health.event.licenseTier == nil)
        #expect(health.event.requestId == nil)
        #expect(health.event.action == nil)
        #expect(health.event.diagnosticEpoch == queue.diagnostics.diagnosticEpoch)
    }

    @Test func disablingBeforeSenderRunsCancelsAndPreventsQueueRecreation() async {
        TelemetryURLProtocol.reset()
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = makeClient(queue: queue)
        client.setConsent(true)
        client.setConsent(false)
        await client.flush()
        await Task.yield()
        #expect(queue.entries.isEmpty)
        #expect(TelemetryURLProtocol.allRequests.isEmpty)
    }

    @Test func optOutCancelsInFlightSendAndNewConsentCannotReviveIt() async throws {
        TelemetryURLProtocol.reset()
        TelemetryURLProtocol.mockResponseDelay = 0.1
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = makeClient(queue: queue)
        client.setConsent(true)
        for _ in 0..<100 where TelemetryURLProtocol.allRequests.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(TelemetryURLProtocol.allRequests.count == 1)
        let oldBody = try #require(TelemetryURLProtocol.allRequestBodies.first)
        client.setConsent(false)
        #expect(queue.entries.isEmpty)
        client.setConsent(true)
        await client.flush()
        try await Task.sleep(for: .milliseconds(110))
        #expect(queue.entries.isEmpty)
        #expect(TelemetryURLProtocol.allRequestBodies.count == 2)
        #expect(TelemetryURLProtocol.allRequestBodies.last != oldBody)
    }

    @Test func retryAfterIsBoundedAndSupportsHTTPDate() {
        #expect(UsageTelemetryClient.retryAfter("99999999", now: .distantPast) == 3600)
        #expect(UsageTelemetryClient.retryAfter("-10", now: .distantPast) == 0)
        #expect(UsageTelemetryClient.retryAfter("not-a-date", now: .distantPast) == nil)
        #expect(UsageTelemetryClient.retryAfter("Tue, 14 Nov 2023 22:13:30 GMT", now: Date(timeIntervalSince1970: 1_700_000_000)) == 10)
    }

    @Test func providerAndErrorEnumsDoNotExposeEndpointOrErrorText() {
        #expect(UsageTelemetryProvider(provider: .friday) == .custom)
        #expect(UsageTelemetryProvider(provider: .custom) == .custom)
        #expect(UsageTelemetryErrorKind(error: TranslateError.contentBlocked(message: "secret text")) == .contentBlocked)
        #expect(UsageTelemetryErrorKind(error: TranslateError.apiError(statusCode: 401, message: "sk-test leaked")) == .apiError)
        #expect(UsageTelemetryErrorKind(error: TranslateError.truncatedOutput) == .truncatedOutput)
        #expect(UsageTelemetryErrorKind(error: TranslateError.invalidOutput) == .invalidOutput)
    }
}

final class TelemetryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 202
    nonisolated(unsafe) static var mockResponseDelay: TimeInterval = 0
    nonisolated(unsafe) static var firstFailureGate: TelemetryFailureGate?
    nonisolated(unsafe) static var onRequest: (@Sendable (Int) -> Void)?
    private let responseLock = NSLock()
    private var wasStopped = false
    nonisolated(unsafe) static var mockStatusCodes: [Int] = []
    nonisolated(unsafe) static var mockErrors: [Error] = []
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var allRequestBodies: [Data] = []
    nonisolated(unsafe) static var allRequests: [URLRequest] = []

    static func reset() {
        mockResponseData = nil
        mockStatusCode = 202
        mockErrors = []
        mockResponseDelay = 0
        firstFailureGate = nil
        onRequest = nil
        mockStatusCodes = []
        lastRequestBody = nil
        allRequestBodies = []
        allRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.allRequests.append(request)
        let body = request.httpBody ?? Self.readBodyStream(from: request)
        Self.lastRequestBody = body
        if let body { Self.allRequestBodies.append(body) }
        Self.onRequest?(Self.allRequests.count)

        if !Self.mockErrors.isEmpty {
            let error = Self.mockErrors.removeFirst()
            if let gate = Self.firstFailureGate {
                Self.firstFailureGate = nil
                gate.hold { [self] in fail(error) }
            } else {
                fail(error)
            }
            return
        }

        let status = Self.mockStatusCodes.isEmpty ? Self.mockStatusCode : Self.mockStatusCodes.removeFirst()
        let data = Self.mockResponseData
        if Self.mockResponseDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.mockResponseDelay) { [self] in
                respond(status: status, data: data)
            }
        } else {
            respond(status: status, data: data)
        }
    }

    private func fail(_ error: Error) {
        responseLock.lock()
        let stopped = wasStopped
        responseLock.unlock()
        guard !stopped else { return }
        client?.urlProtocol(self, didFailWithError: error)
    }

    private func respond(status: Int, data: Data?) {
        responseLock.lock()
        let stopped = wasStopped
        responseLock.unlock()
        guard !stopped else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        responseLock.lock()
        wasStopped = true
        responseLock.unlock()
    }

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

// One-shot, cancellation-aware test signals give causal ordering without
// repeatedly notifying the client or sleeping to guess its internal phase.
final class TelemetryTestSignal: Sendable {
    private let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    init() {
        let pair = AsyncStream<Bool>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }
    func signal() { continuation.yield(true); continuation.finish() }
    func wait() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.stream.first(where: { $0 }) ?? false }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return false
            }
            let received = await group.next() ?? false
            group.cancelAll()
            return received
        }
    }
}

final class TelemetryFailureGate: @unchecked Sendable {
    let held = TelemetryTestSignal()
    private let lock = NSLock()
    private var releaseFailure: (@Sendable () -> Void)?
    private var released = false
    private var overlapped = false
    var secondAttemptOverlapped: Bool { lock.withLock { overlapped } }
    func hold(_ failure: @escaping @Sendable () -> Void) {
        lock.withLock { releaseFailure = failure }
        held.signal()
    }
    func release() {
        let failure = lock.withLock {
            released = true
            let callback = releaseFailure
            releaseFailure = nil
            return callback
        }
        failure?()
    }
    func recordSecondAttempt() { lock.withLock { if !released { overlapped = true } } }
}
