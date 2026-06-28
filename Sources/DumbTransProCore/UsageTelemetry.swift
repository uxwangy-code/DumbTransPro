import Foundation
import OSLog

private let usageTelemetryLogger = Logger(
    subsystem: "com.whimsycode.dumbtrans-pro",
    category: "UsageTelemetry"
)

public enum UsageTelemetryEventName: String, Codable, Sendable, Equatable {
    case appLaunched = "app_launched"
    case translationSucceeded = "translation_succeeded"
    case translationFailed = "translation_failed"
    case translationBlocked = "translation_blocked"
}

public enum UsageTelemetryAction: String, Codable, Sendable, Equatable {
    case rewrite
    case lookup

    public init(action: TranslationAction) {
        switch action {
        case .rewriteToEnglish: self = .rewrite
        case .lookup: self = .lookup
        }
    }
}

public enum UsageTelemetryRoute: String, Codable, Sendable, Equatable {
    case ai
    case offline

    public init?(mode: TranslationMode) {
        switch mode {
        case .ai: self = .ai
        case .offline: self = .offline
        case .needsSetup: return nil
        }
    }
}

public enum UsageTelemetryDirection: String, Codable, Sendable, Equatable {
    case chineseToEnglish = "chinese_to_english"
    case foreignToChinese = "foreign_to_chinese"

    public init(direction: RewriteDirection) {
        switch direction {
        case .chineseToEnglish: self = .chineseToEnglish
        case .foreignToChinese: self = .foreignToChinese
        }
    }
}

public enum UsageTelemetryProvider: String, Codable, Sendable, Equatable {
    case openai
    case zhipu
    case deepseek
    case kimi
    case minimax
    case qwen
    case doubao
    case custom

    public init(provider: AIProvider) {
        switch provider {
        case .openai: self = .openai
        case .zhipu: self = .zhipu
        case .deepseek: self = .deepseek
        case .kimi: self = .kimi
        case .minimax: self = .minimax
        case .qwen: self = .qwen
        case .doubao: self = .doubao
        case .custom, .friday: self = .custom
        }
    }
}

public enum UsageTelemetryErrorKind: String, Codable, Sendable, Equatable {
    case noSelection = "no_selection"
    case needsSetup = "needs_setup"
    case providerLocked = "provider_locked"
    case dailyLimitReached = "daily_limit_reached"
    case offlineLanguageMissing = "offline_language_missing"
    case timeout
    case contentBlocked = "content_blocked"
    case apiError = "api_error"
    case network
    case invalidResponse = "invalid_response"
    case unknown

    public init(error: Error) {
        switch error {
        case TranslateError.requestTimedOut:
            self = .timeout
        case TranslateError.contentBlocked:
            self = .contentBlocked
        case TranslateError.apiError:
            self = .apiError
        case TranslateError.networkError:
            self = .network
        case TranslateError.invalidResponse:
            self = .invalidResponse
        case TranslateError.noAPIKey:
            self = .needsSetup
        default:
            self = .unknown
        }
    }
}

public struct UsageTelemetryContext: Codable, Sendable, Equatable {
    public let appVersion: String
    public let macOSVersion: String

    public init(appVersion: String, macOSVersion: String) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
    }

    public static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> UsageTelemetryContext {
        UsageTelemetryContext(
            appVersion: appVersion(in: bundle),
            macOSVersion: macOSVersion(from: processInfo)
        )
    }

    private static func appVersion(in bundle: Bundle) -> String {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (shortVersion?.isEmpty == false ? shortVersion : nil, build?.isEmpty == false ? build : nil) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        case let (nil, build?): return build
        case (nil, nil): return "Unknown"
        }
    }

    private static func macOSVersion(from processInfo: ProcessInfo) -> String {
        let version = processInfo.operatingSystemVersion
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        return "macOS \(version.majorVersion).\(version.minorVersion)\(patch)"
    }
}

public struct UsageTelemetryEvent: Codable, Sendable, Equatable {
    public let name: UsageTelemetryEventName
    public let action: UsageTelemetryAction?
    public let route: UsageTelemetryRoute?
    public let provider: UsageTelemetryProvider?
    public let direction: UsageTelemetryDirection?
    public let style: String?
    public let licenseTier: LicenseTier?
    public let errorKind: UsageTelemetryErrorKind?

    public init(
        name: UsageTelemetryEventName,
        action: UsageTelemetryAction? = nil,
        route: UsageTelemetryRoute? = nil,
        provider: UsageTelemetryProvider? = nil,
        direction: UsageTelemetryDirection? = nil,
        style: TranslationStyle? = nil,
        licenseTier: LicenseTier? = nil,
        errorKind: UsageTelemetryErrorKind? = nil
    ) {
        self.name = name
        self.action = action
        self.route = route
        self.provider = provider
        self.direction = direction
        self.style = style?.rawValue
        self.licenseTier = licenseTier
        self.errorKind = errorKind
    }

    public static func appLaunched(licenseTier: LicenseTier) -> UsageTelemetryEvent {
        UsageTelemetryEvent(name: .appLaunched, licenseTier: licenseTier)
    }

    public static func translationSucceeded(
        action: UsageTelemetryAction,
        route: UsageTelemetryRoute,
        provider: UsageTelemetryProvider?,
        direction: UsageTelemetryDirection?,
        style: TranslationStyle,
        licenseTier: LicenseTier
    ) -> UsageTelemetryEvent {
        UsageTelemetryEvent(
            name: .translationSucceeded,
            action: action,
            route: route,
            provider: provider,
            direction: direction,
            style: style,
            licenseTier: licenseTier
        )
    }

    public static func translationFailed(
        action: UsageTelemetryAction,
        route: UsageTelemetryRoute,
        provider: UsageTelemetryProvider?,
        direction: UsageTelemetryDirection?,
        style: TranslationStyle?,
        licenseTier: LicenseTier,
        errorKind: UsageTelemetryErrorKind
    ) -> UsageTelemetryEvent {
        UsageTelemetryEvent(
            name: .translationFailed,
            action: action,
            route: route,
            provider: provider,
            direction: direction,
            style: style,
            licenseTier: licenseTier,
            errorKind: errorKind
        )
    }

    public static func translationBlocked(
        action: UsageTelemetryAction,
        provider: UsageTelemetryProvider?,
        licenseTier: LicenseTier,
        errorKind: UsageTelemetryErrorKind
    ) -> UsageTelemetryEvent {
        UsageTelemetryEvent(
            name: .translationBlocked,
            action: action,
            provider: provider,
            licenseTier: licenseTier,
            errorKind: errorKind
        )
    }
}

private struct UsageTelemetryPayload: Codable, Sendable {
    let schemaVersion: Int
    let sentAt: String
    let context: UsageTelemetryContext
    let event: UsageTelemetryEvent
}

public final class UsageTelemetryClient: @unchecked Sendable {
    private let endpoint: URL?
    private let session: URLSession
    private let context: UsageTelemetryContext
    private let now: @Sendable () -> Date

    public init(
        endpoint: URL? = UsageTelemetryClient.endpointURL(),
        session: URLSession = .shared,
        context: UsageTelemetryContext = .current(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.context = context
        self.now = now
    }

    public static func endpointURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: "DTPUsageTelemetryURL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    public func record(_ event: UsageTelemetryEvent, isEnabled: Bool) {
        Task.detached(priority: .utility) { [self] in
            await send(event, isEnabled: isEnabled)
        }
    }

    public func send(_ event: UsageTelemetryEvent, isEnabled: Bool) async {
        guard isEnabled else {
            writeLocalDebug("skipped event=\(event.name.rawValue) reason=disabled")
            usageTelemetryLogger.debug("Skipped usage event: \(event.name.rawValue, privacy: .public), disabled")
            return
        }
        guard let endpoint else {
            usageTelemetryLogger.debug("Skipped usage event: \(event.name.rawValue, privacy: .public), no endpoint")
            return
        }
        writeLocalDebug("sending event=\(event.name.rawValue)")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let payload = UsageTelemetryPayload(
            schemaVersion: 1,
            sentAt: formatter.string(from: now()),
            context: context,
            event: event
        )

        do {
            var request = URLRequest(url: endpoint, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(statusCode) {
                writeLocalDebug("sent event=\(event.name.rawValue) status=\(statusCode)")
                usageTelemetryLogger.info("Sent usage event: \(event.name.rawValue, privacy: .public), status: \(statusCode, privacy: .public)")
            } else {
                writeLocalDebug("rejected event=\(event.name.rawValue) status=\(statusCode)")
                usageTelemetryLogger.error("Usage event rejected: \(event.name.rawValue, privacy: .public), status: \(statusCode, privacy: .public)")
            }
        } catch {
            // Usage telemetry is best-effort and must never affect translation.
            let nsError = error as NSError
            writeLocalDebug("failed event=\(event.name.rawValue) domain=\(nsError.domain) code=\(nsError.code)")
            usageTelemetryLogger.error("Usage event failed: \(event.name.rawValue, privacy: .public), domain: \(nsError.domain, privacy: .public), code: \(nsError.code, privacy: .public)")
        }
    }

    private func writeLocalDebug(_ message: String) {
        guard let endpoint, Self.isLocalEndpoint(endpoint) else { return }
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }
        let directory = libraryURL.appendingPathComponent("Logs/DumbTransPro", isDirectory: true)
        let fileURL = directory.appendingPathComponent("usage-telemetry.log")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let line = "\(formatter.string(from: now())) \(message)\n"

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Local verification diagnostics are best-effort.
        }
    }

    private static func isLocalEndpoint(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
}
