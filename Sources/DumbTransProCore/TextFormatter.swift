import Foundation

public enum RewriteInputKind: Sendable, Equatable {
    case termLike
    case proseLike
}

public enum TextFormatter {
    public static func toKebabCase(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        let lowered = trimmed.lowercased()
        // Keep only alphanumeric, spaces, and hyphens
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return Character(scalar)
            } else {
                return " "
            }
        }
        let joined = String(cleaned)
        // Split on whitespace, filter empty, join with hyphens
        let parts = joined.split(separator: " ", omittingEmptySubsequences: true)
        return parts.joined(separator: "-")
    }

    public static func rewriteInputKind(_ input: String) -> RewriteInputKind {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .termLike }

        if trimmed.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) {
            return .proseLike
        }

        if trimmed.rangeOfCharacter(from: sentencePunctuation) != nil {
            return .proseLike
        }

        let chineseCount = trimmed.unicodeScalars.filter(Self.isChineseScalar).count
        if chineseCount >= 15 {
            return .proseLike
        }

        if chineseCount >= 8 && sentenceMarkers.contains(where: { trimmed.contains($0) }) {
            return .proseLike
        }

        if trimmed.count >= 28 {
            return .proseLike
        }

        return .termLike
    }

    private static let sentencePunctuation = CharacterSet(charactersIn: "。！？!?；;：:，,、")
    private static let sentenceMarkers = [
        "这是", "这个", "那个", "这些", "那些", "我们", "用户",
        "可以", "需要", "应该", "不能", "不会", "不要", "没有",
        "如果", "因为", "所以", "但是", "然后", "时候", "支持",
        "导致", "发现", "保证", "提供", "处理"
    ]

    private static func isChineseScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value)
    }
}
