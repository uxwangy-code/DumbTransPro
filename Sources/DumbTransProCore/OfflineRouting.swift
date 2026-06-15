import Foundation

/// 翻译触发时的模式判定：有 key 走 AI；没 key 但离线可用走离线；否则提示去配置。
/// 纯函数，便于单测；不依赖任何 macOS 15 类型，可在全系统编译。
public enum TranslationMode: Equatable, Sendable {
    case ai
    case offline
    case needsSetup

    public static func resolve(hasAPIKey: Bool, offlineAvailable: Bool) -> TranslationMode {
        if hasAPIKey { return .ai }
        if offlineAvailable { return .offline }
        return .needsSetup
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
