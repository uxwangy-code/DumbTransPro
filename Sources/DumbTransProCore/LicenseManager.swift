import Foundation

public enum LicenseTier: String, Codable, Sendable, Equatable {
    case free
    case pro
}

/// 翻译动作触发前的分层判定结果。
public enum TranslationGate: Equatable, Sendable {
    case allowed
    case providerLocked(AIProvider)
    case dailyLimitReached(limit: Int)
}

public enum LicenseError: Error, LocalizedError, Equatable {
    case emptyKey
    case invalidKey(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .emptyKey: return "请输入 License Key"
        case .invalidKey(let reason): return "License 无效：\(reason)"
        case .network(let reason): return "暂时无法验证 License（\(reason)），请检查网络后重试；如果当前网络访问海外服务不稳定，可尝试挂🪜后重试"
        }
    }
}

public enum LicenseVerificationProblem: Equatable, Sendable {
    case network(String)
}

public struct LicenseVerification: Sendable, Equatable {
    public let isValid: Bool
    public let failureReason: String?

    public init(isValid: Bool, failureReason: String? = nil) {
        self.isValid = isValid
        self.failureReason = failureReason
    }
}

public protocol LicenseVerifying: Sendable {
    /// 返回校验结果；key 无效（不存在/退款/拒付）走返回值，只有网络层失败才抛错。
    func verify(key: String, incrementUses: Bool) async throws -> LicenseVerification
}

public struct CompositeLicenseVerifier: LicenseVerifying {
    private let verifiers: [any LicenseVerifying]

    public init(verifiers: [any LicenseVerifying]) {
        self.verifiers = verifiers
    }

    public func verify(key: String, incrementUses: Bool) async throws -> LicenseVerification {
        var invalidReasons: [String] = []
        var networkError: Error?

        for verifier in verifiers {
            do {
                let result = try await verifier.verify(key: key, incrementUses: incrementUses)
                if result.isValid {
                    return result
                }
                if let reason = result.failureReason, !reason.isEmpty {
                    invalidReasons.append(reason)
                }
            } catch {
                networkError = error
            }
        }

        if let networkError {
            throw networkError
        }

        return LicenseVerification(
            isValid: false,
            failureReason: invalidReasons.first ?? "key 不存在或已停用"
        )
    }
}

public enum LicenseVerifierFactory {
    public static func production(bundle: Bundle = .main) -> any LicenseVerifying {
        var verifiers: [any LicenseVerifying] = []
        if let verifyURL = LicenseGatewayVerifier.verifyURL(bundle: bundle) {
            verifiers.append(LicenseGatewayVerifier(verifyURL: verifyURL))
        }
        verifiers.append(GumroadLicenseVerifier())
        return CompositeLicenseVerifier(verifiers: verifiers)
    }
}

public enum LicensePurchase {
    public static let fallbackURL = URL(string: "https://uxwangy-code.github.io/DumbTransPro/")!

    public static func url(bundle: Bundle = .main) -> URL {
        guard let raw = bundle.object(forInfoDictionaryKey: "DTPLicensePurchaseURL") as? String else {
            return fallbackURL
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return fallbackURL }
        return url
    }
}

public struct LicenseGatewayVerifier: LicenseVerifying {
    private let session: URLSession
    private let verifyURL: URL
    private let appName: String

    public init(
        session: URLSession = .shared,
        verifyURL: URL,
        appName: String = "DumbTransPro"
    ) {
        self.session = session
        self.verifyURL = verifyURL
        self.appName = appName
    }

    public static func verifyURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: "DTPLicenseVerifyURL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    public func verify(key: String, incrementUses: Bool) async throws -> LicenseVerification {
        var request = URLRequest(url: verifyURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "license_key": key,
            "increment_uses": incrementUses,
            "app": appName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.network("无效响应")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.network("HTTP \(http.statusCode)")
        }

        guard (200..<300).contains(http.statusCode) else {
            return LicenseVerification(isValid: false, failureReason: failureReason(in: json) ?? "HTTP \(http.statusCode)")
        }

        let success = json["valid"] as? Bool ?? json["is_valid"] as? Bool ?? false
        guard success else {
            return LicenseVerification(isValid: false, failureReason: failureReason(in: json) ?? "key 不存在或已停用")
        }

        return LicenseVerification(isValid: true)
    }

    private func failureReason(in json: [String: Any]) -> String? {
        if let reason = json["reason"] as? String, !reason.isEmpty {
            return reason
        }
        if let failureReason = json["failure_reason"] as? String, !failureReason.isEmpty {
            return failureReason
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}

/// Gumroad License Key 校验。Gumroad 托管签发/停用，app 端只做一次 HTTPS 校验，无自建后端。
public struct GumroadLicenseVerifier: LicenseVerifying {
    /// 在 Gumroad 后台创建商品并勾选 "Generate license keys" 后，把商品的 product_id 填到这里再发版。
    public static let productID = "Qona8hwEBPez88DAZeBWZw=="
    /// Gumroad 商品购买页，设置面板"获取 License"跳转用。
    public static let purchaseURL = URL(string: "https://whimsycode.gumroad.com/l/dumbtranspro")!

    private static let verifyURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func verify(key: String, incrementUses: Bool) async throws -> LicenseVerification {
        var request = URLRequest(url: Self.verifyURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "product_id", value: Self.productID),
            URLQueryItem(name: "license_key", value: key),
            URLQueryItem(name: "increment_uses_count", value: incrementUses ? "true" : "false"),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.network("无效响应")
        }
        // Gumroad 对无效 key 返回 404 + JSON 体；非 JSON 一律视作服务异常
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.network("HTTP \(http.statusCode)")
        }

        guard json["success"] as? Bool == true else {
            let message = (json["message"] as? String) ?? "key 不存在或与商品不匹配"
            return LicenseVerification(isValid: false, failureReason: message)
        }
        if let purchase = json["purchase"] as? [String: Any] {
            if purchase["refunded"] as? Bool == true {
                return LicenseVerification(isValid: false, failureReason: "订单已退款")
            }
            if purchase["chargebacked"] as? Bool == true || purchase["disputed"] as? Bool == true {
                return LicenseVerification(isValid: false, failureReason: "订单存在拒付争议")
            }
        }
        return LicenseVerification(isValid: true)
    }
}

/// Free/Pro 分层与 license 生命周期：
/// - key 存 Keychain，不落盘明文
/// - 激活时在线校验一次；之后每隔几天静默复验
/// - 断网复验失败时保留已验证的 Pro；明确无效（退款/拒付）才摘除 key
@MainActor
public final class LicenseManager: ObservableObject {
    public static let freeProviders: Set<AIProvider> = [.openai, .zhipu]
    public static let freeProviderNames = "OpenAI、智谱 GLM"
    public static let freeDailyLimit = 30
    /// 静默复验间隔（天）
    static let revalidationIntervalDays = 3

    @Published public private(set) var tier: LicenseTier = .free
    @Published public private(set) var lastVerificationProblem: LicenseVerificationProblem?

    private let defaults: UserDefaults
    private let keychainService: String
    private let verifier: any LicenseVerifying
    private let meter: DailyUsageMeter
    private let now: () -> Date

    private let licenseAccount = "license-key"
    private let lastVerifiedKey = "license.lastVerifiedAt"

    public convenience init() {
        self.init(
            defaults: .standard,
            keychainService: "com.whimsycode.dumbtrans-pro",
            verifier: LicenseVerifierFactory.production()
        )
    }

    init(
        defaults: UserDefaults,
        keychainService: String,
        verifier: any LicenseVerifying,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.keychainService = keychainService
        self.verifier = verifier
        self.now = now
        self.meter = DailyUsageMeter(defaults: defaults, now: now)
        if storedKey() != nil, lastVerifiedAt() != nil {
            tier = .pro
        }
    }

    // MARK: - Gating

    public func gate(provider: AIProvider?) -> TranslationGate {
        if tier == .pro { return .allowed }
        if let provider, !Self.freeProviders.contains(provider) {
            return .providerLocked(provider)
        }
        if meter.count() >= Self.freeDailyLimit {
            return .dailyLimitReached(limit: Self.freeDailyLimit)
        }
        return .allowed
    }

    /// 翻译成功后调用；Pro 不计数。
    public func recordTranslation() {
        guard tier == .free else { return }
        meter.increment()
    }

    public var remainingToday: Int {
        max(0, Self.freeDailyLimit - meter.count())
    }

    public var menuTitle: String {
        switch tier {
        case .pro: return "Pro 已激活"
        case .free: return "免费版 · 今日剩余 \(remainingToday) 次"
        }
    }

    public var maskedKey: String? {
        guard let key = storedKey() else { return nil }
        return "····" + key.suffix(8)
    }

    public var proStatusDetail: String? {
        guard tier == .pro else { return nil }
        switch lastVerificationProblem {
        case .network:
            let lastText = lastVerifiedAt().map { Self.displayDate($0) } ?? "未知"
            return "最近无法联网复验，上次验证：\(lastText)。License 已保留，可尝试挂🪜后重试。"
        case nil:
            guard let last = lastVerifiedAt() else { return nil }
            return "上次验证：\(Self.displayDate(last))"
        }
    }

    // MARK: - License lifecycle

    public func activate(key rawKey: String) async throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LicenseError.emptyKey }

        let result = try await verifier.verify(key: key, incrementUses: true)
        guard result.isValid else {
            throw LicenseError.invalidKey(result.failureReason ?? "未知原因")
        }
        try? KeychainHelper.save(service: keychainService, account: licenseAccount, data: key)
        defaults.set(now().timeIntervalSince1970, forKey: lastVerifiedKey)
        lastVerificationProblem = nil
        tier = .pro
    }

    public func deactivate() {
        try? KeychainHelper.delete(service: keychainService, account: licenseAccount)
        defaults.removeObject(forKey: lastVerifiedKey)
        lastVerificationProblem = nil
        tier = .free
    }

    /// 启动时调用：有 key 且距上次成功复验超过间隔才发网络请求；失败不打扰用户。
    public func revalidateIfNeeded() async {
        guard let key = storedKey() else { return }
        if tier == .pro,
           let last = lastVerifiedAt(),
           now().timeIntervalSince(last) < Double(Self.revalidationIntervalDays) * 86400 {
            return
        }
        do {
            let result = try await verifier.verify(key: key, incrementUses: false)
            if result.isValid {
                defaults.set(now().timeIntervalSince1970, forKey: lastVerifiedKey)
                lastVerificationProblem = nil
                tier = .pro
            } else {
                // 明确无效（退款/拒付/key 被停用）才摘除
                deactivate()
            }
        } catch {
            // 网络失败：只要本机曾成功验证过，就保留 Pro，避免把可恢复的联网问题伪装成 license 丢失。
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastVerificationProblem = .network(reason)
            tier = lastVerifiedAt() == nil ? .free : .pro
        }
    }

    // MARK: - Helpers

    private func storedKey() -> String? {
        guard let key = try? KeychainHelper.load(service: keychainService, account: licenseAccount),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }

    private func lastVerifiedAt() -> Date? {
        let timestamp = defaults.double(forKey: lastVerifiedKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
