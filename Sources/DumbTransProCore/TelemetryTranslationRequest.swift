import Foundation

public enum UsageTelemetryOutcome: Sendable { case succeeded, failed, blocked, cancelled }
public enum TelemetryFailureStage: String, Codable, Sendable { case selection, setup, engine }
public enum TelemetryDelivery: String, Codable, Sendable {
    case panelShown = "panel_shown"
    case pasteRequested = "paste_requested"
    case manualCopyAvailable = "manual_copy_available"
}
public enum TelemetryDurationBucket: String, Codable, Sendable {
    case under1s = "under_1s"
    case oneTo3s = "1_to_3s"
    case threeTo10s = "3_to_10s"
    case tenTo30s = "10_to_30s"
    case over30s = "over_30s"

    public init(elapsed: TimeInterval) {
        switch max(0, elapsed) {
        case ..<1: self = .under1s
        case ..<3: self = .oneTo3s
        case ..<10: self = .threeTo10s
        case ..<30: self = .tenTo30s
        default: self = .over30s
        }
    }
}

public struct TelemetryTranslationRequest: Sendable, Equatable {
    public let requestId: String
    public let requestStartedAt: String
    let generation: UInt64
    let startedUptime: TimeInterval
    let action: UsageTelemetryAction
    let licenseTier: LicenseTier
}

func telemetryTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
