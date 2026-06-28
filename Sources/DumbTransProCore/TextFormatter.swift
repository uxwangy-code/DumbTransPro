import Foundation

public enum RewriteInputKind: Sendable, Equatable {
    case termLike
    case proseLike
}

public enum RewriteDirection: Sendable, Equatable {
    case chineseToEnglish
    case foreignToChinese
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

        if looksLikeChineseQuestion(trimmed) {
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

    public static func rewriteDirection(for input: String) -> RewriteDirection {
        let scalars = input.unicodeScalars
        let chineseCount = scalars.filter(Self.isChineseScalar).count
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) && !Self.isChineseScalar($0) }.count

        return chineseCount >= max(1, letterCount / 2)
            ? .chineseToEnglish
            : .foreignToChinese
    }

    public static func repairForeignToChineseTranslation(source: String, translation: String) -> String {
        let normalizedSource = normalizeForeignQuestion(source)
        guard let repaired = aiModelQuestionTranslations[normalizedSource] else {
            return translation
        }

        return repaired
    }

    private static let sentencePunctuation = CharacterSet(charactersIn: "。！？!?；;：:，,、")
    private static let sentenceMarkers = [
        "这是", "这个", "那个", "这些", "那些", "我们", "用户",
        "可以", "需要", "应该", "不能", "不会", "不要", "没有",
        "如果", "因为", "所以", "但是", "然后", "时候", "支持",
        "导致", "发现", "保证", "提供", "处理"
    ]
    private static let chineseQuestionMarkers = [
        "什么", "谁", "哪里", "哪个", "怎么", "怎样", "为什么", "为何",
        "多少", "是否", "是不是", "能不能", "会不会",
        "你是", "我是", "它是", "这是"
    ]
    private static let terminalQuestionParticles = ["吗", "呢"]
    private static let singleCharQuestionPatterns = [
        "在哪",
        "哪些",
        "哪儿",
        "哪天", "哪年", "哪月", "哪位", "哪家", "哪种", "哪类", "哪款", "哪次", "哪边", "哪一",
        "几个", "几天", "几年", "几月", "几点", "几号", "几次", "几位", "几家", "几张", "几页", "几分钟", "几秒", "几遍", "几种", "几类", "几岁"
    ]
    private static let aiModelQuestionTranslations = [
        "what model are you": "你是什么模型？",
        "what model are you using": "你用的是什么模型？",
        "which model are you using": "你用的是哪个模型？",
        "what model are you based on": "你基于什么模型？",
    ]

    private static func normalizeForeignQuestion(_ text: String) -> String {
        let lowered = text.lowercased()
        let normalized = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(normalized).split(separator: " ").joined(separator: " ")
    }

    private static func looksLikeChineseQuestion(_ text: String) -> Bool {
        let chineseCount = text.unicodeScalars.filter(Self.isChineseScalar).count
        guard chineseCount >= 2 else { return false }

        if chineseQuestionMarkers.contains(where: { text.contains($0) }) {
            return true
        }

        if terminalQuestionParticles.contains(where: { text.hasSuffix($0) }) {
            return true
        }

        return singleCharQuestionPatterns.contains(where: { text.contains($0) })
    }

    private static func isChineseScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value)
    }
}
