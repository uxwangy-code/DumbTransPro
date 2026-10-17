import Foundation
import Testing
@testable import DumbTransProCore

@MainActor
private final class MemoryLicenseStorage: LicenseKeyStoring {
    var key: String?
    var failsSave = false
    var failsDelete = false
    func load() throws -> String? { key }
    func save(_ key: String) throws {
        if failsSave { throw LicenseError.storage }
        self.key = key
    }
    func delete() throws {
        if failsDelete { throw LicenseError.storage }
        key = nil
    }
}

private actor PausedRevalidation: LicenseVerifying {
    var pending: CheckedContinuation<LicenseVerification, Never>?
    var started: CheckedContinuation<Void, Never>?
    func verify(key: String, incrementUses: Bool) async throws -> LicenseVerification {
        if incrementUses { return LicenseVerification(isValid: true) }
        return await withCheckedContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilPaused() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume(valid: Bool) {
        pending?.resume(returning: LicenseVerification(isValid: valid, failureReason: "invalid"))
        pending = nil
    }
}

@MainActor
struct LicenseReliabilityTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test.license.memory.\(UUID())")! }
    private func manager(_ defaults: UserDefaults, _ storage: MemoryLicenseStorage,
                         _ verifier: PausedRevalidation) -> LicenseManager {
        LicenseManager(defaults: defaults, keychainService: "unused-in-memory-tests", verifier: verifier,
                       now: { Date(timeIntervalSince1970: 1_800_000_000) }, keyStorage: storage)
    }

    @Test func keychainFailureCannotGrantProOrPersistVerification() async {
        let d = defaults(), storage = MemoryLicenseStorage(), verifier = PausedRevalidation()
        storage.failsSave = true
        let sut = manager(d, storage, verifier)
        await #expect(throws: LicenseError.storage) { try await sut.activate(key: "FAKE") }
        #expect(sut.tier == .free)
        #expect(d.object(forKey: "license.lastVerifiedAt") == nil)
        #expect(manager(d, storage, verifier).tier == .free)
    }

    @Test func lateRevalidationCannotUndoDeactivationEvenWhenDeletionFails() async throws {
        let d = defaults(), storage = MemoryLicenseStorage(), verifier = PausedRevalidation()
        let sut = manager(d, storage, verifier)
        try await sut.activate(key: "OLD")
        d.set(1.0, forKey: "license.lastVerifiedAt")
        let task = Task { await sut.revalidateIfNeeded() }
        await verifier.waitUntilPaused()
        storage.failsDelete = true
        sut.deactivate()
        await verifier.resume(valid: true)
        await task.value
        #expect(sut.tier == .free)
        let restarted = manager(d, storage, verifier)
        await restarted.revalidateIfNeeded()
        #expect(restarted.tier == .free)
    }

    @Test func oldInvalidResponseCannotRemoveNewActivation() async throws {
        let d = defaults(), storage = MemoryLicenseStorage(), verifier = PausedRevalidation()
        let sut = manager(d, storage, verifier)
        try await sut.activate(key: "OLD")
        d.set(1.0, forKey: "license.lastVerifiedAt")
        let task = Task { await sut.revalidateIfNeeded() }
        await verifier.waitUntilPaused()
        try await sut.activate(key: "NEW")
        await verifier.resume(valid: false)
        await task.value
        #expect(sut.tier == .pro)
        #expect(storage.key == "NEW")
        #expect(manager(d, storage, verifier).tier == .pro)
    }
}
