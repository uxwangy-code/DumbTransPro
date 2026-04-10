import Carbon.HIToolbox

public enum TranslationMode: String, CaseIterable, Sendable {
    case dumb = "瞎翻"
    case proper = "正经"
    case fancy = "文学"

    public var hotkeyLabel: String {
        switch self {
        case .dumb: return "⌘⇧R"
        case .proper: return "⌘⇧T"
        case .fancy: return "⌘⇧Y"
        }
    }

    public var keyCode: UInt32 {
        switch self {
        case .dumb: return UInt32(kVK_ANSI_R)
        case .proper: return UInt32(kVK_ANSI_T)
        case .fancy: return UInt32(kVK_ANSI_Y)
        }
    }

    public var hotkeyID: UInt32 {
        switch self {
        case .dumb: return 1
        case .proper: return 2
        case .fancy: return 3
        }
    }

    public var prompt: String {
        switch self {
        case .dumb:
            return """
            你是一个中文转英文文件名工具。规则：
            1. 将每个中文字/词逐个翻译成对应的英文单词
            2. 用空格分隔，全部小写
            3. 必须逐字直译，不要意译，不要合并，不要优化语法
            4. 只输出翻译结果，不要任何其他内容

            示例：
            好好学习 → good good study
            天天向上 → day day up
            未命名文件夹 → unnamed file folder
            我的项目 → my project
            """
        case .proper:
            return """
            你是一个中文转英文文件名工具。规则：
            1. 将中文翻译成自然、地道的英文
            2. 用空格分隔，全部小写
            3. 输出简洁的英文，像一个英语母语者会起的文件名
            4. 只输出翻译结果，不要任何其他内容

            示例：
            好好学习 → study hard
            天天向上 → keep improving
            未命名文件夹 → untitled folder
            我的项目 → my project
            """
        case .fancy:
            return """
            你是一个中文转英文文件名工具，风格要求：使用极其高级、文学化的英文词汇，越有格调越好。规则：
            1. 使用学术或文学级别的高级词汇，展现深厚的文化底蕴
            2. 用空格分隔，全部小写
            3. 风格要像一个常春藤文学教授或英国贵族会使用的措辞
            4. 只输出翻译结果，不要任何其他内容

            示例：
            好好学习 → diligent pursuit of erudition
            天天向上 → perpetual ascent to eminence
            未命名文件夹 → enigmatic repository
            我的项目 → magnum opus
            """
        }
    }

    public static func from(hotkeyID: UInt32) -> TranslationMode? {
        allCases.first { $0.hotkeyID == hotkeyID }
    }
}
