import Foundation

public enum TelemetryConsentState: String, Codable, Sendable {
    case undecided, enabled, disabled
}

@MainActor
public final class TelemetryConsentStore {
    public static let policyVersion = "2026-10-05"
    private let defaults: UserDefaults
    private let decisionKey: String
    private let policyKey: String
    private let buildChannel: TelemetryBuildChannel

    public init(defaults: UserDefaults = .standard, buildChannel: TelemetryBuildChannel = .current) {
        self.defaults = defaults
        self.buildChannel = buildChannel
        let prefix = buildChannel == .production ? "usageTelemetry.v3" : "usageTelemetry.development.v3"
        decisionKey = "\(prefix).decision"
        policyKey = "\(prefix).policyVersion"
    }

    public var state: TelemetryConsentState {
        let decision = defaults.string(forKey: decisionKey)
        if decision == TelemetryConsentState.disabled.rawValue { return .disabled }
        if decision == TelemetryConsentState.enabled.rawValue,
           defaults.string(forKey: policyKey) == Self.policyVersion { return .enabled }
        // A historical explicit off remains off. Historical default/on never authorizes v3.
        if buildChannel == .production, defaults.object(forKey: "shareAnonymousUsageData") != nil,
           !defaults.bool(forKey: "shareAnonymousUsageData") { return .disabled }
        return .undecided
    }

    public func setAllowed(_ allowed: Bool) {
        defaults.set(allowed ? TelemetryConsentState.enabled.rawValue : TelemetryConsentState.disabled.rawValue,
                     forKey: decisionKey)
        defaults.set(Self.policyVersion, forKey: policyKey)
    }
}
