import Foundation

/// A random identifier for this app's data installation, never a hardware identifier.
@MainActor
public protocol TelemetryIdentityStoring: AnyObject {
    func existingID() throws -> String?
    func getOrCreateID() throws -> String
    func resetID() throws -> String
}

@MainActor
public final class FileTelemetryIdentityStore: TelemetryIdentityStoring {
    private let storageURL: URL

    public init(storageURL: URL = TelemetryStorage.directory.appendingPathComponent("identity.json")) {
        self.storageURL = storageURL
    }

    public func existingID() throws -> String? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return nil }
        let value = try JSONDecoder().decode(String.self, from: Data(contentsOf: storageURL))
        guard let uuid = UUID(uuidString: value), uuid.uuid.6 >> 4 == 4 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    public func getOrCreateID() throws -> String {
        if let existing = try existingID() { return existing }
        return try resetID()
    }

    public func resetID() throws -> String {
        let value = UUID().uuidString.lowercased()
        try TelemetryStorage.write(JSONEncoder().encode(value), to: storageURL)
        return value
    }
}

@MainActor
public final class MemoryTelemetryIdentityStore: TelemetryIdentityStoring {
    private var value: String?
    public init() {}
    public func existingID() throws -> String? { value }
    public func getOrCreateID() throws -> String {
        if let value { return value }
        return try resetID()
    }
    public func resetID() throws -> String {
        let id = UUID().uuidString.lowercased()
        value = id
        return id
    }
}

public enum TelemetryStorage {
    public static var directory: URL { directory(for: .current) }

    public static func directory(for channel: TelemetryBuildChannel) -> URL {
        // Keep the production path stable across upgrades. Debug data never
        // shares its identity, queue, or diagnostic counters.
        let path = channel == .production ? "DumbTransPro/Telemetry" : "DumbTransPro/Telemetry-Development"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(path, isDirectory: true)
    }

    static func write(_ data: Data, to destination: URL) throws {
        var directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try directory.setResourceValues(excluded)
        try data.write(to: destination, options: .atomic)
        var file = destination
        try file.setResourceValues(excluded)
    }
}
