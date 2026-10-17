import Foundation
import Combine
import Network

public enum UsageTelemetryEventName: String, Codable, Sendable, Equatable {
    case appLaunched = "app_launched"
    case telemetryEnabled = "telemetry_enabled"
    case translationStarted = "translation_started"
    case translationCancelled = "translation_cancelled"
    case telemetryHealth = "telemetry_health"
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
    case accessibilityDenied = "accessibility_denied"
    case clipboardBusy = "clipboard_busy"
    case invalidOutput = "invalid_output"
    case truncatedOutput = "truncated_output"
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
        case TranslateError.invalidOutput:
            self = .invalidOutput
        case TranslateError.truncatedOutput:
            self = .truncatedOutput
        case TranslateError.noAPIKey:
            self = .needsSetup
        default:
            self = .unknown
        }
    }
}

public enum TelemetryBuildChannel: String, Codable, Sendable {
    case production, development
    public static var current: Self {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }
}

public struct UsageTelemetryContext: Codable, Sendable, Equatable {
    public let appVersion: String
    public let macOSVersion: String
    public let buildChannel: TelemetryBuildChannel

    public init(appVersion: String, macOSVersion: String, buildChannel: TelemetryBuildChannel = .development) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.buildChannel = buildChannel
    }

    public static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> Self {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let version = [short, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        let os = processInfo.operatingSystemVersion
        let channel = TelemetryBuildChannel.current
        return Self(appVersion: version.isEmpty ? "Unknown" : version,
                    macOSVersion: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", buildChannel: channel)
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
    public let requestId: String?
    public let requestStartedAt: String?
    public let durationBucket: TelemetryDurationBucket?
    public let failureStage: TelemetryFailureStage?
    public let delivery: TelemetryDelivery?
    public let diagnosticEpoch: String?
    public let droppedOverflow: Int?
    public let droppedExpired: Int?
    public let droppedCorrupt: Int?
    public let rejectedPermanent: Int?

    public init(name: UsageTelemetryEventName, action: UsageTelemetryAction? = nil,
                route: UsageTelemetryRoute? = nil, provider: UsageTelemetryProvider? = nil,
                direction: UsageTelemetryDirection? = nil, style: TranslationStyle? = nil,
                licenseTier: LicenseTier? = nil, errorKind: UsageTelemetryErrorKind? = nil,
                requestId: String? = nil, requestStartedAt: String? = nil,
                durationBucket: TelemetryDurationBucket? = nil, failureStage: TelemetryFailureStage? = nil,
                delivery: TelemetryDelivery? = nil, diagnostics: TelemetryDiagnostics? = nil) {
        self.name = name; self.action = action; self.route = route; self.provider = provider
        self.direction = direction; self.style = style?.rawValue; self.licenseTier = licenseTier
        self.errorKind = errorKind; self.requestId = requestId; self.requestStartedAt = requestStartedAt
        self.durationBucket = durationBucket; self.failureStage = failureStage; self.delivery = delivery
        diagnosticEpoch = diagnostics?.diagnosticEpoch; droppedOverflow = diagnostics?.droppedOverflow
        droppedExpired = diagnostics?.droppedExpired; droppedCorrupt = diagnostics?.droppedCorrupt
        rejectedPermanent = diagnostics?.rejectedPermanent
    }

    var isValid: Bool {
        let hasDiagnostics = diagnosticEpoch != nil || droppedOverflow != nil || droppedExpired != nil
            || droppedCorrupt != nil || rejectedPermanent != nil
        if name == .telemetryHealth {
            return diagnosticEpoch.flatMap(UUID.init(uuidString:)) != nil
                && [droppedOverflow, droppedExpired, droppedCorrupt, rejectedPermanent].allSatisfy { ($0 ?? -1) >= 0 }
                && action == nil && route == nil && provider == nil && direction == nil && style == nil
                && licenseTier == nil && requestId == nil && requestStartedAt == nil && durationBucket == nil
                && errorKind == nil && failureStage == nil && delivery == nil
        }
        guard !hasDiagnostics else { return false }
        if name == .appLaunched || name == .telemetryEnabled {
            return action == nil && route == nil && provider == nil && direction == nil && style == nil
                && requestId == nil && requestStartedAt == nil && durationBucket == nil
                && errorKind == nil && failureStage == nil && delivery == nil
        }
        guard action != nil, licenseTier != nil, requestId.flatMap(UUID.init(uuidString:)) != nil,
              requestStartedAt != nil else { return false }
        if name == .translationStarted {
            return durationBucket == nil && errorKind == nil && failureStage == nil && delivery == nil
        }
        guard durationBucket != nil else { return false }
        switch name {
        case .translationSucceeded: return route != nil && errorKind == nil && failureStage == nil
        case .translationFailed: return errorKind != nil && failureStage != nil && delivery == nil
        case .translationBlocked: return errorKind != nil && failureStage == nil && delivery == nil
        case .translationCancelled: return errorKind == nil && failureStage == nil && delivery == nil
        default: return false
        }
    }

    public static func appLaunched(licenseTier: LicenseTier) -> Self { Self(name: .appLaunched, licenseTier: licenseTier) }

    // Source compatibility while call sites migrate. Incomplete legacy request events are rejected by v3 validation.
    public static func translationSucceeded(action: UsageTelemetryAction, route: UsageTelemetryRoute,
        provider: UsageTelemetryProvider?, direction: UsageTelemetryDirection?, style: TranslationStyle, licenseTier: LicenseTier) -> Self {
        Self(name: .translationSucceeded, action: action, route: route, provider: provider, direction: direction, style: style, licenseTier: licenseTier)
    }
    public static func translationFailed(action: UsageTelemetryAction, route: UsageTelemetryRoute,
        provider: UsageTelemetryProvider?, direction: UsageTelemetryDirection?, style: TranslationStyle?, licenseTier: LicenseTier,
        errorKind: UsageTelemetryErrorKind) -> Self {
        Self(name: .translationFailed, action: action, route: route, provider: provider, direction: direction, style: style, licenseTier: licenseTier, errorKind: errorKind)
    }
    public static func translationBlocked(action: UsageTelemetryAction, provider: UsageTelemetryProvider?,
        licenseTier: LicenseTier, errorKind: UsageTelemetryErrorKind) -> Self {
        Self(name: .translationBlocked, action: action, provider: provider, licenseTier: licenseTier, errorKind: errorKind)
    }
}

public struct UsageTelemetryPayload: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let eventId: String
    public let installationId: String
    public let occurredAt: String
    public let policyVersion: String
    public let collectionMode: String
    public let context: UsageTelemetryContext
    public let event: UsageTelemetryEvent
}

/// Owns consent, request lifecycle, persisted queue, and the sole sender on one executor.
@MainActor
public final class UsageTelemetryClient: ObservableObject {
    @Published public private(set) var consentState: TelemetryConsentState
    @Published public private(set) var installationID: String?
    public var needsConsentDecision: Bool { consentState == .undecided }

    private let endpoint: URL?
    private let session: URLSession
    private let context: UsageTelemetryContext
    private let consentStore: TelemetryConsentStore
    private let identityStore: any TelemetryIdentityStoring
    private let queue: TelemetryEventQueue
    private let now: @Sendable () -> Date
    private let uptime: @Sendable () -> TimeInterval
    private let retryDelayNanoseconds: UInt64
    private let retrySleep: @Sendable (UInt64) async throws -> Void
    private var networkRecoveryGeneration: UInt64 = 0
    private var generation: UInt64 = 0
    private var activeRequests: Set<String> = []
    private var sender: Task<Void, Never>?
    private var retryWait: (id: UUID, task: Task<Void, Never>, canWakeForNetwork: Bool)?
    private var monitor: NWPathMonitor?
    private var lastHealthSnapshot: TelemetryDiagnostics?

    public init(endpoint: URL? = UsageTelemetryClient.endpointURL(), session: URLSession = .shared,
                context: UsageTelemetryContext = .current(), consentStore: TelemetryConsentStore? = nil,
                identityStore: (any TelemetryIdentityStoring)? = nil,
                queue: TelemetryEventQueue? = nil,
                now: @escaping @Sendable () -> Date = { Date() },
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                retryDelayNanoseconds: UInt64 = 1_000_000_000, observeNetworkChanges: Bool = true,
                retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        let directory = TelemetryStorage.directory(for: context.buildChannel)
        let consentStore = consentStore ?? TelemetryConsentStore(buildChannel: context.buildChannel)
        let identityStore = identityStore ?? FileTelemetryIdentityStore(storageURL: directory.appendingPathComponent("identity.json"))
        let queue = queue ?? TelemetryEventQueue(storageURL: directory.appendingPathComponent("queue.json"))
        self.endpoint = endpoint.flatMap { Self.endpointAllowed($0, for: context.buildChannel) ? $0 : nil }
        self.session = session; self.context = context; self.consentStore = consentStore
        self.identityStore = identityStore; self.queue = queue; self.now = now; self.uptime = uptime
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.retrySleep = retrySleep
        consentState = consentStore.state
        installationID = try? identityStore.existingID()
        if consentState == .enabled {
            installationID = try? identityStore.getOrCreateID()
            queue.prune(now: now())
            startSending()
        } else {
            queue.clear()
        }
        if self.endpoint != nil && observeNetworkChanges {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in self?.networkDidBecomeAvailable() }
            }
            self.monitor = monitor
            monitor.start(queue: DispatchQueue(label: "com.whimsycode.dumbtrans-pro.telemetry-network"))
        }
    }

    deinit { monitor?.cancel(); sender?.cancel(); retryWait?.task.cancel() }

    public nonisolated static func endpointURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: "DTPUsageTelemetryURL") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    public func setConsent(_ allowed: Bool) {
        let changed = consentState != (allowed ? .enabled : .disabled)
        if !allowed {
            generation &+= 1
            sender?.cancel(); sender = nil
            retryWait?.task.cancel(); retryWait = nil
            activeRequests.removeAll()
            queue.clear()
            lastHealthSnapshot = nil
        }
        consentStore.setAllowed(allowed)
        consentState = allowed ? .enabled : .disabled
        guard allowed else { return }
        installationID = try? identityStore.getOrCreateID()
        if changed { enqueue(UsageTelemetryEvent(name: .telemetryEnabled)) }
        startSending()
    }

    /// Call only after presenting the old ID's deletion route to the user.
    @discardableResult public func resetInstallationID() -> String? {
        guard consentState == .enabled else { return nil }
        generation &+= 1
        sender?.cancel(); sender = nil
        retryWait?.task.cancel(); retryWait = nil
        activeRequests.removeAll(); queue.clear()
        installationID = try? identityStore.resetID()
        queue.resetDiagnostics()
        lastHealthSnapshot = nil
        enqueue(UsageTelemetryEvent(name: .telemetryEnabled))
        return installationID
    }

    public func recordAppLaunched(licenseTier: LicenseTier) { enqueue(.appLaunched(licenseTier: licenseTier)) }

    public func beginTranslation(action: UsageTelemetryAction, licenseTier: LicenseTier) -> TelemetryTranslationRequest? {
        guard consentState == .enabled, installationID != nil else { return nil }
        let request = TelemetryTranslationRequest(requestId: UUID().uuidString.lowercased(),
            requestStartedAt: telemetryTimestamp(now()), generation: generation, startedUptime: uptime(), action: action, licenseTier: licenseTier)
        activeRequests.insert(request.requestId)
        enqueue(UsageTelemetryEvent(name: .translationStarted, action: action, licenseTier: licenseTier,
                                    requestId: request.requestId, requestStartedAt: request.requestStartedAt))
        return request
    }

    public func finishTranslation(_ request: TelemetryTranslationRequest?, outcome: UsageTelemetryOutcome,
        route: UsageTelemetryRoute? = nil, provider: UsageTelemetryProvider? = nil,
        direction: UsageTelemetryDirection? = nil, style: TranslationStyle? = nil,
        errorKind: UsageTelemetryErrorKind? = nil, failureStage: TelemetryFailureStage? = nil,
        delivery: TelemetryDelivery? = nil) {
        guard consentState == .enabled, let request, request.generation == generation,
              activeRequests.contains(request.requestId) else { return }
        let name: UsageTelemetryEventName
        switch outcome {
        case .succeeded: name = .translationSucceeded
        case .failed: name = .translationFailed
        case .blocked: name = .translationBlocked
        case .cancelled: name = .translationCancelled
        }
        let event = UsageTelemetryEvent(name: name, action: request.action, route: route, provider: provider,
            direction: direction, style: style, licenseTier: request.licenseTier, errorKind: errorKind,
            requestId: request.requestId, requestStartedAt: request.requestStartedAt,
            durationBucket: TelemetryDurationBucket(elapsed: uptime() - request.startedUptime), failureStage: failureStage, delivery: delivery)
        guard event.isValid else { return }
        activeRequests.remove(request.requestId)
        enqueue(event)
    }

    public func record(_ event: UsageTelemetryEvent, isEnabled: Bool) {
        guard isEnabled else { return }
        enqueue(event)
    }

    public func networkDidBecomeAvailable() {
        guard consentState == .enabled else { return }
        networkRecoveryGeneration &+= 1
        queue.prune(now: now())
        // Keep the one sender and any in-flight HTTP request. Only its local
        // offline backoff is interruptible; an explicit Retry-After is honored.
        if retryWait?.canWakeForNetwork == true { retryWait?.task.cancel() }
        startSending()
    }

    /// Drain queued events; consent changes cancel this wait and its underlying network request.
    public func flush() async { startSending(); await sender?.value }

    private func enqueue(_ event: UsageTelemetryEvent) {
        guard consentState == .enabled, let installationID, event.isValid else { return }
        let payload = UsageTelemetryPayload(schemaVersion: 3, eventId: UUID().uuidString.lowercased(),
            installationId: installationID, occurredAt: telemetryTimestamp(now()), policyVersion: TelemetryConsentStore.policyVersion,
            collectionMode: "explicit_opt_in", context: context, event: event)
        queue.append(payload, now: now())
        startSending()
    }

    private func addHealthSnapshotIfNeeded() {
        guard consentState == .enabled, queue.diagnostics.hasDrops, queue.diagnostics != lastHealthSnapshot else { return }
        lastHealthSnapshot = queue.diagnostics
        enqueue(UsageTelemetryEvent(name: .telemetryHealth, diagnostics: queue.diagnostics))
    }

    private func startSending() {
        guard consentState == .enabled, installationID != nil, endpoint != nil, sender == nil else { return }
        let token = generation
        sender = Task { [weak self] in
            guard let self else { return }
            await self.drain(generation: token)
            if self.generation == token { self.sender = nil }
        }
    }

    private func drain(generation token: UInt64) async {
        guard let endpoint, consentState == .enabled, generation == token, !Task.isCancelled else { return }
        addHealthSnapshotIfNeeded()
        var attempts = 0
        while consentState == .enabled, generation == token, !Task.isCancelled {
            queue.prune(now: now())
            guard let entry = queue.entries.first else { return }
            // Never replay another build channel's persisted history, including
            // deliberately injected or old shared queues. Do not relabel it.
            guard entry.payload.context.buildChannel == context.buildChannel,
                  Self.endpointAllowed(endpoint, for: entry.payload.context.buildChannel) else {
                queue.remove(eventId: entry.payload.eventId)
                continue
            }
            var request = URLRequest(url: endpoint, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = entry.body
            var retryAfter: TimeInterval?
            let recoveryAtRequestStart = networkRecoveryGeneration
            do {
                let (_, response) = try await session.data(for: request)
                guard consentState == .enabled, generation == token, !Task.isCancelled else { return }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 200 || status == 202 {
                    queue.remove(eventId: entry.payload.eventId)
                    attempts = 0
                    addHealthSnapshotIfNeeded()
                    continue
                }
                if !Self.shouldRetry(statusCode: status) {
                    queue.remove(eventId: entry.payload.eventId)
                    if entry.payload.event.name != .telemetryHealth {
                        queue.recordPermanentRejection()
                        addHealthSnapshotIfNeeded()
                    }
                    attempts = 0
                    continue
                }
                retryAfter = Self.retryAfter(http?.value(forHTTPHeaderField: "Retry-After"), now: now())
            } catch {
                guard consentState == .enabled, generation == token, !Task.isCancelled else { return }
            }
            attempts += 1
            // A recovered path may be reported before this older HTTP attempt
            // finishes failing. Remember that notification instead of entering
            // a fresh offline sleep after recovery. Server Retry-After wins.
            if retryAfter == nil && networkRecoveryGeneration != recoveryAtRequestStart { continue }
            let base = Double(retryDelayNanoseconds) / 1_000_000_000
            let delay = retryAfter ?? min(3600, base * pow(2, Double(min(attempts - 1, 12)))) * Double.random(in: 0.8...1.2)
            let waitID = UUID()
            let sleep = retrySleep
            let waitTask = Task<Void, Never> {
                do { try await sleep(UInt64(min(3600, max(0, delay)) * 1_000_000_000)) }
                catch { /* Network recovery or consent change wakes the sender. */ }
            }
            retryWait = (waitID, waitTask, retryAfter == nil)
            await waitTask.value
            // An old consent generation may finish cancellation after a new
            // generation has already begun waiting; do not clear its handle.
            if retryWait?.id == waitID { retryWait = nil }
        }
    }

    private nonisolated static func endpointAllowed(_ endpoint: URL, for channel: TelemetryBuildChannel) -> Bool {
        guard channel == .development else { return true }
        return ["localhost", "127.0.0.1", "::1", "[::1]", "telemetry-staging.whimsycode.com"]
            .contains(endpoint.host?.lowercased() ?? "")
    }

    static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 0 || statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return min(3600, max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { min(3600, max(0, $0.timeIntervalSince(now))) }
    }
}
