import Foundation
import Testing
@testable import DumbTransProCore

private let localTelemetryEndpoint: URL? = {
    guard let raw = ProcessInfo.processInfo.environment["DTP_TEST_ENDPOINT"],
          let url = URL(string: raw), url.scheme == "http",
          ["localhost", "127.0.0.1"].contains(url.host?.lowercased() ?? "") else { return nil }
    return url
}()

@MainActor
struct TelemetryLocalCaptureTests {
    @Test(.enabled(if: localTelemetryEndpoint != nil))
    func capturesV3LifecycleUsingIsolatedApplicationData() async throws {
        let endpoint = try #require(localTelemetryEndpoint)
        let suiteName = "telemetry-local-capture.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dtp-telemetry-capture-\(UUID())")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let consent = TelemetryConsentStore(defaults: defaults)
        consent.setAllowed(true)
        let queue = TelemetryEventQueue(storageURL: directory.appendingPathComponent("queue.json"))
        let client = UsageTelemetryClient(endpoint: endpoint, context: UsageTelemetryContext(
            appVersion: "1.5.5 (155)", macOSVersion: "macOS local verification", buildChannel: .development),
            consentStore: consent, identityStore: FileTelemetryIdentityStore(storageURL: directory.appendingPathComponent("identity.json")),
            queue: queue, observeNetworkChanges: false)
        defer { client.setConsent(false) }
        client.recordAppLaunched(licenseTier: .free)
        let request = client.beginTranslation(action: .rewrite, licenseTier: .free)
        client.finishTranslation(request, outcome: .succeeded, route: .ai, provider: .openai,
                                 direction: .chineseToEnglish, style: .natural, delivery: .manualCopyAvailable)
        await client.flush()
        #expect(queue.entries.isEmpty)
        #expect(queue.diagnostics.rejectedPermanent == 0)
    }
}
