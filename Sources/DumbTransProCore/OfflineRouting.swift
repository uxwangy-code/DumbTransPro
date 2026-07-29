import Foundation

/// 用户明确选择的翻译引擎。与 `TranslationMode` 分开，避免把持久化偏好
/// 和一次触发时解析出的可用状态混在一起。
public enum TranslationEngine: String, CaseIterable, Identifiable, Sendable {
    case ai
    case offline

    public var id: String { rawValue }
}

struct OfflineLanguagePair: Sendable, Equatable {
    let sourceIdentifier: String
    let targetIdentifier: String

    static let chineseToEnglish = Self(
        sourceIdentifier: "zh-Hans",
        targetIdentifier: "en"
    )
    static let englishToChinese = Self(
        sourceIdentifier: "en",
        targetIdentifier: "zh-Hans"
    )
}

/// 翻译触发时的模式判定：未设置偏好时保留旧版自动路由；一旦用户明确选择，
/// 就只使用该引擎，不在 AI 与离线之间静默回退。
/// 纯函数，便于单测；不依赖任何 macOS 15 类型，可在全系统编译。
public enum TranslationMode: Equatable, Sendable {
    case ai
    case offline
    case needsSetup

    public static func resolve(
        preference: TranslationEngine?,
        hasAPIKey: Bool,
        offlineAvailable: Bool
    ) -> TranslationMode {
        switch preference {
        case .ai:
            return hasAPIKey ? .ai : .needsSetup
        case .offline:
            return offlineAvailable ? .offline : .needsSetup
        case nil:
            if hasAPIKey { return .ai }
            if offlineAvailable { return .offline }
            return .needsSetup
        }
    }

}

/// 离线「用中文写英文」的结果整形：复用与 AI 路径相同的 词/句 分流——
/// 词条 → kebab 文件名，句子 → 去空白的英文。引擎只负责给出纯英文，
/// 这里把「offline 也能出 kebab 文件名」的产品逻辑收在一处、可单测。
public enum OfflineRewriteFormatter {
    public static func format(originalInput: String, english: String) -> String {
        switch TextFormatter.rewriteInputKind(originalInput) {
        case .termLike:
            return TextFormatter.toKebabCase(english)
        case .proseLike:
            return english.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
