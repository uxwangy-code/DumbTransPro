import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
@Suite(.serialized)
struct TelemetryV3Tests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "telemetry-v3.\(UUID())")!
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func client(defaults: UserDefaults? = nil, queue: TelemetryEventQueue? = nil) -> UsageTelemetryClient {
        UsageTelemetryClient(endpoint: nil, consentStore: TelemetryConsentStore(defaults: defaults ?? self.defaults()), identityStore: MemoryTelemetryIdentityStore(), queue: queue ?? TelemetryEventQueue(storageURL: nil), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    @Test func oldDefaultOnRequiresChoiceAndExplicitOffSurvivesMigration() {
        let oldOn = defaults()
        oldOn.set(true, forKey: "shareAnonymousUsageData")
        #expect(TelemetryConsentStore(defaults: oldOn, buildChannel: .production).state == .undecided)
        let oldOff = defaults()
        oldOff.set(false, forKey: "shareAnonymousUsageData")
        #expect(TelemetryConsentStore(defaults: oldOff, buildChannel: .production).state == .disabled)
        let store = TelemetryConsentStore(defaults: oldOn, buildChannel: .production)
        store.setAllowed(false)
        #expect(TelemetryConsentStore(defaults: oldOn, buildChannel: .production).state == .disabled)
        store.setAllowed(true)
        #expect(TelemetryConsentStore(defaults: oldOn, buildChannel: .production).state == .enabled)
    }

    @Test func developmentAndProductionStorageAreSeparateAndProductionPathRetainsIdentity() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #expect(TelemetryStorage.directory(for: .production) == appSupport.appendingPathComponent("DumbTransPro/Telemetry", isDirectory: true))
        #expect(TelemetryStorage.directory(for: .development) != TelemetryStorage.directory(for: .production))
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let identityURL = dir.appendingPathComponent("DumbTransPro/Telemetry/identity.json")
        let oldStore = FileTelemetryIdentityStore(storageURL: identityURL)
        let existing = try oldStore.getOrCreateID()
        let freshQueue = TelemetryEventQueue(storageURL: dir.appendingPathComponent("queue.json"))
        let consent = TelemetryConsentStore(defaults: defaults(), buildChannel: .production)
        consent.setAllowed(true)
        let upgraded = UsageTelemetryClient(endpoint: nil,
            context: UsageTelemetryContext(appVersion: "new", macOSVersion: "macOS", buildChannel: .production),
            consentStore: consent, identityStore: FileTelemetryIdentityStore(storageURL: identityURL), queue: freshQueue)
        #expect(upgraded.installationID == existing)
    }

    @Test func developmentConsentDoesNotAuthorizeProductionOrOverrideItsChoice() {
        let defaults = defaults()
        let production = TelemetryConsentStore(defaults: defaults, buildChannel: .production)
        let development = TelemetryConsentStore(defaults: defaults, buildChannel: .development)
        development.setAllowed(true)
        #expect(development.state == .enabled)
        #expect(production.state == .undecided)
        production.setAllowed(false)
        development.setAllowed(true)
        #expect(production.state == .disabled)
    }

    @Test func noIdentityOrHistoryExistsBeforeChoice() {
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = client(queue: queue)
        client.recordAppLaunched(licenseTier: .free)
        #expect(client.beginTranslation(action: .rewrite, licenseTier: .free) == nil)
        #expect(client.installationID == nil)
        #expect(queue.entries.isEmpty)
        client.setConsent(true)
        #expect(queue.entries.count == 1)
        #expect(queue.entries.first?.payload.event.name == .telemetryEnabled)
    }

    @Test func installationIdentityPersistsAndResetChangesIt() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("identity.json")
        let store = FileTelemetryIdentityStore(storageURL: url)
        #expect(try store.existingID() == nil)
        let first = try store.getOrCreateID()
        #expect(UUID(uuidString: first) != nil)
        #expect(first.split(separator: "-")[2].first == "4")
        #expect(try FileTelemetryIdentityStore(storageURL: url).getOrCreateID() == first)
        #expect(try MemoryTelemetryIdentityStore().getOrCreateID() != first)
        #expect(try store.resetID() != first)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func disableRetainsIdentityClearsQueueAndRejectsLateTerminal() {
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = client(queue: queue)
        client.setConsent(true)
        let id = client.installationID
        let request = client.beginTranslation(action: .lookup, licenseTier: .pro)
        client.setConsent(false)
        #expect(client.installationID == id)
        #expect(queue.entries.isEmpty)
        client.setConsent(true)
        client.finishTranslation(request, outcome: .succeeded, route: .ai, delivery: .panelShown)
        #expect(queue.entries.count == 1)
        #expect(client.installationID == id)
    }

    @Test func cancellationAndDuplicateResultsProduceOnlyOneTerminal() throws {
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = client(queue: queue)
        client.setConsent(true)
        let request = client.beginTranslation(action: .rewrite, licenseTier: .free)
        client.finishTranslation(request, outcome: .cancelled)
        client.finishTranslation(request, outcome: .succeeded, route: .ai, delivery: .pasteRequested)
        let events = queue.entries.map(\.payload.event)
        #expect(events.map(\.name) == [.telemetryEnabled, .translationStarted, .translationCancelled])
        #expect(events[1].requestId == events[2].requestId)
        #expect(events[1].requestStartedAt == "2023-11-14T22:13:20.000Z")
        #expect(events[1].requestStartedAt == events[2].requestStartedAt)
        #expect(events[2].durationBucket != nil)
        #expect(events[2].delivery == nil)
    }

    @Test func persistedPayloadRemainsIdenticalAcrossRestart() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("queue.json")
        let queue = TelemetryEventQueue(storageURL: url)
        let client = client(queue: queue)
        client.setConsent(true)
        let first = try #require(queue.entries.first)
        let restored = TelemetryEventQueue(storageURL: url)
        #expect(restored.entries.first?.body == first.body)
        #expect(restored.entries.first?.payload.eventId == first.payload.eventId)
        let object = try #require(JSONSerialization.jsonObject(with: first.body) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 3)
        #expect(object["collectionMode"] as? String == "explicit_opt_in")
        #expect(object["policyVersion"] as? String == "2026-10-05")
        #expect(object["sentAt"] == nil)
    }

    @Test func overflowingQueueEvictsWholeRequestAndCountsDroppedEvents() {
        let queue = TelemetryEventQueue(storageURL: nil, maxCount: 3)
        let client = client(queue: queue)
        client.setConsent(true)
        let one = client.beginTranslation(action: .lookup, licenseTier: .free)
        client.finishTranslation(one, outcome: .cancelled)
        _ = client.beginTranslation(action: .rewrite, licenseTier: .free)
        _ = client.beginTranslation(action: .rewrite, licenseTier: .free)
        #expect(!queue.entries.contains { $0.payload.event.requestId == one?.requestId })
        #expect(queue.diagnostics.droppedOverflow == 3)
    }

    @Test func expiredAndCorruptFilesDoNotTouchOtherData() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("queue.json")
        let unrelated = dir.appendingPathComponent("settings.json")
        try Data("keep me".utf8).write(to: unrelated)
        try Data("broken".utf8).write(to: url)
        let corrupt = TelemetryEventQueue(storageURL: url)
        #expect(corrupt.entries.isEmpty)
        #expect(corrupt.diagnostics.droppedCorrupt == 1)
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep me")
        let queue = TelemetryEventQueue(storageURL: nil, maxAge: 60)
        let client = client(queue: queue)
        client.setConsent(true)
        queue.prune(now: Date(timeIntervalSince1970: 1_700_000_061))
        #expect(queue.entries.isEmpty)
        #expect(queue.diagnostics.droppedExpired == 1)
    }

    @Test func byteLimitAndDiagnosticCountsSurviveRestart() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("queue.json")
        let queue = TelemetryEventQueue(storageURL: url, maxBytes: 100)
        let client = client(queue: queue)
        client.setConsent(true)
        #expect(queue.entries.isEmpty)
        #expect(queue.diagnostics.droppedOverflow == 1)
        #expect(try Data(contentsOf: url).count <= 100)
        let restored = TelemetryEventQueue(storageURL: url)
        #expect(restored.diagnostics.droppedOverflow == 1)
        #expect(restored.diagnostics.diagnosticEpoch == queue.diagnostics.diagnosticEpoch)
    }

    @Test func failedPreparationKeepsOneRequestWithSelectionStage() {
        let queue = TelemetryEventQueue(storageURL: nil)
        let client = client(queue: queue)
        client.setConsent(true)
        let request = client.beginTranslation(action: .lookup, licenseTier: .free)
        client.finishTranslation(request, outcome: .failed, errorKind: .noSelection, failureStage: .selection)
        let event = queue.entries.last?.payload.event
        #expect(event?.name == .translationFailed)
        #expect(event?.requestId == request?.requestId)
        #expect(event?.failureStage == .selection)
        #expect(event?.errorKind == .noSelection)
        #expect(event?.route == nil)
        #expect(event?.delivery == nil)
    }

    @Test func monotonicDurationBucketsUseElapsedTime() {
        #expect(TelemetryDurationBucket(elapsed: 0.2) == .under1s)
        #expect(TelemetryDurationBucket(elapsed: 1) == .oneTo3s)
        #expect(TelemetryDurationBucket(elapsed: 3) == .threeTo10s)
        #expect(TelemetryDurationBucket(elapsed: 10) == .tenTo30s)
        #expect(TelemetryDurationBucket(elapsed: 30) == .over30s)
    }
}
