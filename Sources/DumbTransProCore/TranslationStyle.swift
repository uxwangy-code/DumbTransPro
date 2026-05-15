import Carbon.HIToolbox

public enum TranslationStyle: String, CaseIterable, Identifiable, Sendable {
    case plain
    case natural
    case elegant

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: return "浅白"
        case .natural: return "自然"
        case .elegant: return "典雅"
        }
    }

    public var description: String {
        switch self {
        case .plain:
            return "使用简单常见词汇，尽量直白易懂。"
        case .natural:
            return "默认推荐，翻译自然、准确、日常。"
        case .elegant:
            return "更有文采，偏高级词汇或文学表达。"
        }
    }

    public var filenamePrompt: String {
        switch self {
        case .plain:
            return """
            你是一个中文转英文文件名工具。风格：浅白、简单、直白。规则：
            1. 将中文翻译成最常见、最容易看懂的英文词汇
            2. 避免复杂语法、少见单词、文学化表达
            3. 用空格分隔，全部小写
            4. 只输出翻译结果，不要任何其他内容

            示例：
            好好学习 → study well
            天天向上 → get better every day
            未命名文件夹 → unnamed folder
            我的项目 → my project
            """
        case .natural:
            return """
            你是一个中文转英文文件名工具。风格：自然、准确、地道。规则：
            1. 将中文翻译成自然、日常、准确的英文
            2. 输出简洁的英文，像英语母语者会起的文件名
            3. 用空格分隔，全部小写
            4. 只输出翻译结果，不要任何其他内容

            示例：
            好好学习 → study hard
            天天向上 → keep improving
            未命名文件夹 → untitled folder
            我的项目 → my project
            """
        case .elegant:
            return """
            你是一个中文转英文文件名工具。风格：典雅、高级、有文采。规则：
            1. 使用更正式、更高级、更有文学感的英文表达
            2. 可以适度使用学术或文学词汇，但不要牺牲含义准确性
            3. 用空格分隔，全部小写
            4. 只输出翻译结果，不要任何其他内容

            示例：
            好好学习 → diligent pursuit of erudition
            天天向上 → perpetual ascent to eminence
            未命名文件夹 → enigmatic repository
            我的项目 → magnum opus
            """
        }
    }

    public var lookupPrompt: String {
        switch self {
        case .plain:
            return """
            翻译以下文本为简体中文。风格：浅白、简单、直白。
            规则：
            1. 使用常见词和短句，避免复杂表达
            2. 让中文读者能快速理解原意
            3. 只输出翻译结果，不要任何解释或额外内容
            """
        case .natural:
            return """
            翻译以下文本为简体中文。风格：自然、准确、日常。
            规则：
            1. 保持原意准确
            2. 使用自然流畅的现代中文
            3. 只输出翻译结果，不要任何解释或额外内容
            """
        case .elegant:
            return """
            翻译以下文本为简体中文。风格：典雅、有文采、富有表达力。
            规则：
            1. 保持原意准确
            2. 可以使用更有韵味、更文学化的中文表达
            3. 如果原文是技术、事实或操作说明，优先保证清楚准确
            4. 只输出翻译结果，不要任何解释或额外内容
            """
        }
    }
}

public enum TranslationAction: CaseIterable, Sendable {
    case rewriteToEnglish
    case lookup

    public var title: String {
        switch self {
        case .rewriteToEnglish: return "中文转英文"
        case .lookup: return "划词翻译"
        }
    }

    public var hotkeyLabel: String {
        switch self {
        case .rewriteToEnglish: return "⌘⇧R"
        case .lookup: return "⌘⇧F"
        }
    }

    public var keyCode: UInt32 {
        switch self {
        case .rewriteToEnglish: return UInt32(kVK_ANSI_R)
        case .lookup: return UInt32(kVK_ANSI_F)
        }
    }

    public var hotkeyID: UInt32 {
        switch self {
        case .rewriteToEnglish: return 1
        case .lookup: return 2
        }
    }

    public static func from(hotkeyID: UInt32) -> TranslationAction? {
        allCases.first { $0.hotkeyID == hotkeyID }
    }
}
