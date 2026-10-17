import Foundation

public struct TelemetryDiagnostics: Codable, Sendable, Equatable {
    public let diagnosticEpoch: String
    public fileprivate(set) var droppedOverflow: Int = 0
    public fileprivate(set) var droppedExpired: Int = 0
    public fileprivate(set) var droppedCorrupt: Int = 0
    public fileprivate(set) var rejectedPermanent: Int = 0
    public init() { diagnosticEpoch = UUID().uuidString.lowercased() }
    var hasDrops: Bool { droppedOverflow > 0 || droppedExpired > 0 || droppedCorrupt > 0 || rejectedPermanent > 0 }
    var isValid: Bool {
        UUID(uuidString: diagnosticEpoch) != nil
            && [droppedOverflow, droppedExpired, droppedCorrupt, rejectedPermanent].allSatisfy { $0 >= 0 }
    }
}

public struct TelemetryQueuedEvent: Codable, Sendable {
    public let payload: UsageTelemetryPayload
    public let body: Data
    private enum CodingKeys: String, CodingKey { case body }
    init(payload: UsageTelemetryPayload) throws {
        self.payload = payload
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        body = try encoder.encode(payload)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        body = try container.decode(Data.self, forKey: .body)
        payload = try JSONDecoder().decode(UsageTelemetryPayload.self, from: body)
        guard payload.schemaVersion == 3, payload.event.isValid,
              UUID(uuidString: payload.eventId) != nil,
              UUID(uuidString: payload.installationId) != nil,
              Self.date(payload.occurredAt) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(body, forKey: .body)
    }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

/// Bounded atomic persistence. Owned by UsageTelemetryClient's MainActor executor.
@MainActor
public final class TelemetryEventQueue {
    public private(set) var entries: [TelemetryQueuedEvent] = []
    public private(set) var diagnostics = TelemetryDiagnostics()
    private let storageURL: URL?
    private let diagnosticsURL: URL?
    private let maxCount: Int
    private let maxBytes: Int
    private let maxAge: TimeInterval

    public init(storageURL: URL? = TelemetryStorage.directory.appendingPathComponent("queue.json"),
                maxCount: Int = 1_000, maxBytes: Int = 2 * 1_024 * 1_024, maxAge: TimeInterval = 7 * 24 * 3_600) {
        self.storageURL = storageURL
        self.diagnosticsURL = storageURL?.deletingPathExtension().appendingPathExtension("diagnostics.json")
        self.maxCount = max(1, maxCount); self.maxBytes = max(1, maxBytes); self.maxAge = max(0, maxAge)
        if let url = diagnosticsURL, FileManager.default.fileExists(atPath: url.path) {
            if let value = try? JSONDecoder().decode(TelemetryDiagnostics.self, from: Data(contentsOf: url)), value.isValid {
                diagnostics = value
            } else {
                diagnostics.droppedCorrupt += 1
                try? FileManager.default.removeItem(at: url)
                persistDiagnostics()
            }
        }
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            entries = try JSONDecoder().decode([TelemetryQueuedEvent].self, from: Data(contentsOf: storageURL))
        } catch {
            diagnostics.droppedCorrupt += 1
            try? FileManager.default.removeItem(at: storageURL)
            persistDiagnostics()
        }
    }

    func append(_ payload: UsageTelemetryPayload, now: Date) {
        guard payload.event.isValid, let entry = try? TelemetryQueuedEvent(payload: payload) else { return }
        entries.append(entry)
        prune(now: now)
    }

    public func prune(now: Date) {
        var expiredRequests = Set<String>()
        var expiredEvents = Set<String>()
        for entry in entries {
            guard let date = TelemetryQueuedEvent.date(entry.payload.occurredAt), now.timeIntervalSince(date) <= maxAge else {
                if let request = entry.payload.event.requestId { expiredRequests.insert(request) }
                else { expiredEvents.insert(entry.payload.eventId) }
                continue
            }
        }
        let oldCount = entries.count
        entries.removeAll { entry in
            expiredEvents.contains(entry.payload.eventId) || entry.payload.event.requestId.map { expiredRequests.contains($0) } == true
        }
        add(&diagnostics.droppedExpired, oldCount - entries.count)
        while entries.count > maxCount || persistedByteCount > maxBytes {
            guard let oldest = entries.first else { break }
            let count = entries.count
            if let requestID = oldest.payload.event.requestId {
                entries.removeAll { $0.payload.event.requestId == requestID }
            } else {
                entries.removeFirst()
            }
            add(&diagnostics.droppedOverflow, count - entries.count)
        }
        persist()
        persistDiagnostics()
    }

    func remove(eventId: String) {
        entries.removeAll { $0.payload.eventId == eventId }
        persist()
    }

    public func clear() {
        entries.removeAll()
        if let storageURL { try? FileManager.default.removeItem(at: storageURL) }
    }

    func recordPermanentRejection() {
        add(&diagnostics.rejectedPermanent, 1)
        persistDiagnostics()
    }

    func resetDiagnostics() {
        diagnostics = TelemetryDiagnostics()
        persistDiagnostics()
    }

    private var persistedByteCount: Int { (try? JSONEncoder().encode(entries).count) ?? Int.max }
    private func persist() {
        guard let storageURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? TelemetryStorage.write(data, to: storageURL)
    }
    private func persistDiagnostics() {
        guard let diagnosticsURL, let data = try? JSONEncoder().encode(diagnostics) else { return }
        try? TelemetryStorage.write(data, to: diagnosticsURL)
    }
    private func add(_ value: inout Int, _ count: Int) { value += min(count, Int.max - value) }
}
