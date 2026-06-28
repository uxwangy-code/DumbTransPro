import Foundation

public enum SettingsPanelSection: String, CaseIterable, Identifiable, Sendable {
    case aiService = "ai-service"
    case translation = "translation"
    case pro = "pro"
    case feedbackAbout = "feedback-about"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aiService: return "AI 服务"
        case .translation: return "翻译设置"
        case .pro: return "Pro"
        case .feedbackAbout: return "反馈与关于"
        }
    }

    public var summary: String {
        switch self {
        case .aiService: return "服务商、Endpoint、API Key、Model"
        case .translation: return "快捷键、翻译风格、离线翻译"
        case .pro: return "License 激活与停用"
        case .feedbackAbout: return "邮件反馈、版本、官网、GitHub、隐私"
        }
    }

    public var systemImage: String {
        switch self {
        case .aiService: return "sparkles"
        case .translation: return "keyboard"
        case .pro: return "checkmark.seal"
        case .feedbackAbout: return "envelope"
        }
    }
}

public struct SettingsFeedbackContext: Sendable, Equatable {
    public let appVersion: String
    public let macOSVersion: String
    public let activeProviderName: String
    public let licenseStatus: String

    public init(
        appVersion: String,
        macOSVersion: String,
        activeProviderName: String,
        licenseStatus: String
    ) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.activeProviderName = activeProviderName
        self.licenseStatus = licenseStatus
    }
}

public struct SettingsPanelSidebarItemState: Sendable, Equatable {
    public let section: SettingsPanelSection
    public let isSelected: Bool

    public init(section: SettingsPanelSection, selectedSection: SettingsPanelSection) {
        self.section = section
        self.isSelected = section == selectedSection
    }

    public var accessibilityLabel: String {
        section.title
    }

    public var accessibilityValue: String? {
        isSelected ? "已选中" : nil
    }
}

public enum SettingsFeedbackMail {
    public static let recipient = "hi@whimsycode.com"
    public static let subject = "瞎翻 Pro 反馈"

    public static func context(
        activeProviderName: String?,
        licenseTier: LicenseTier,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> SettingsFeedbackContext {
        SettingsFeedbackContext(
            appVersion: appVersion(in: bundle),
            macOSVersion: macOSVersion(from: processInfo),
            activeProviderName: activeProviderName?.isEmpty == false ? activeProviderName! : "Not selected",
            licenseStatus: licenseTier == .pro ? "Pro" : "Free"
        )
    }

    public static func url(context: SettingsFeedbackContext) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(for: context)),
        ]
        return components.url!
    }

    private static func body(for context: SettingsFeedbackContext) -> String {
        """
        请在这里描述问题或建议：


        ---
        App Version: \(context.appVersion)
        macOS: \(context.macOSVersion)
        Provider: \(context.activeProviderName)
        License: \(context.licenseStatus)
        """
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
