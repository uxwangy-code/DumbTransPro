import Carbon.HIToolbox

public enum TranslationStyle: String, CaseIterable, Identifiable, Sendable {
    case plain
    case natural
    case elegant

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: return "土翻"
        case .natural: return "正翻"
        case .elegant: return "装翻"
        }
    }

    public var description: String {
        switch self {
        case .plain:
            return "中式直译,差生专用,会英语的不要选。"
        case .natural:
            return "默认推荐,追求自然准确,正常人首选。"
        case .elegant:
            return "偶尔抽风会出文言文或者散文,没有文学修养不要轻易尝试。"
        }
    }

    public var filenameSystem: String {
        switch self {
        case .plain:
            return """
            你是「中式直译」中转英文件名工具。灵魂是「好好学习 → good good study」的调性。

            核心规则:
            1. 逐字逐词直译,中文怎么拆,英文就按那个顺序写
            2. 保留中文语法和思维,不要按英语母语习惯重组
            3. 不追求英语规范,追求"中文骨架透过英文皮肤露出来"的反差感
            4. 全部小写,空格分隔
            5. 只输出翻译结果,不解释、不带引号、不要重述输入
            """
        case .natural:
            return """
            你是一个中文转英文文件名工具。风格：自然、准确、地道。
            1. 将中文翻译成自然、日常、准确的英文
            2. 输出简洁的英文,像英语母语者会起的文件名
            3. 用空格分隔,全部小写
            4. 只输出翻译结果,不要任何其他内容
            """
        case .elegant:
            return """
            你是「典雅风」中转英文件名工具。

            调性:让人觉得这个文件出自一位穿燕尾服、喝下午茶的老贵族之手。
            1. 用偏古典 / 学术 / 拉丁色彩的英文词,允许夹古英语风
            2. 允许直接借用拉丁文短语(如 ad astra, opus magnum, sine die, ex libris)
            3. 允许使用大多数英语母语者都不常用的高级词
            4. 不追求字面对译,追求"读起来就装"的感觉
            5. 全部小写,空格分隔
            6. 只输出翻译结果,不解释、不带引号
            """
        }
    }

    public var filenameExamples: [(input: String, output: String)] {
        switch self {
        case .plain:
            return [
                ("好好学习", "good good study"),
                ("天天向上", "day day up"),
                ("加油", "add oil"),
                ("人山人海", "people mountain people sea"),
                ("不见不散", "no see no go"),
                ("没办法", "no way"),
                ("看情况", "look situation"),
                ("小心翼翼", "small heart wing wing"),
                ("你行你上", "you can you up"),
                ("老司机", "old driver"),
            ]
        case .natural:
            return [
                ("好好学习", "study hard"),
                ("天天向上", "keep improving"),
                ("未命名文件夹", "untitled folder"),
                ("我的项目", "my project"),
            ]
        case .elegant:
            return [
                ("好好学习", "ardent erudition"),
                ("天天向上", "ad astra perpetuum"),
                ("未命名文件夹", "enigma codex"),
                ("我的项目", "opus magnum"),
                ("笔记", "marginalia"),
                ("草稿", "palimpsest in fieri"),
                ("日记", "diurnal chronicle"),
            ]
        }
    }

    public var proseSystem: String {
        switch self {
        case .plain:
            return """
            你是「土翻」中文转英文工具,但这次输入是一句话或一段文字,不是文件名。

            调性:像英语基础一般的人认真把话说明白。简单、直白、口语一点,但必须是正常英文。
            1. 不要逐字硬翻成 "good good study" 那种文件名风格
            2. 用常见基础词汇和短句,避免高级词、书面腔、学术腔
            3. 保持原意,语法基本正确,读起来像普通人能看懂的话
            4. 正常使用空格、大小写和标点
            5. 只输出英文翻译,不解释、不带引号、不要重述输入
            """
        case .natural:
            return """
            你是中文转英文翻译工具。输入是一句话或一段文字。
            1. 将中文翻译成自然、准确、日常的英文
            2. 保持原意和语气,不要改写成文件名或标题
            3. 正常使用空格、大小写和标点
            4. 只输出英文翻译,不要任何解释或额外内容
            """
        case .elegant:
            return """
            你是「装翻」中文转英文工具。输入是一句话或一段文字。

            调性:正式、精致、学术感更强,用更高级、更专业、更有分量的英文表达。
            1. 保持原意准确,不要为了炫技改变事实
            2. 优先使用更凝练、正式、专业的词汇和句式
            3. 可以有学术、策展、产品策略文案的质感,但不要生僻到影响理解
            4. 正常使用空格、大小写和标点
            5. 只输出英文翻译,不解释、不带引号
            """
        }
    }

    public var proseExamples: [(input: String, output: String)] {
        switch self {
        case .plain:
            return [
                ("这个按钮可以打开设置面板。", "This button can open the settings panel."),
                ("漂亮的页面会让用户更想继续使用。", "A beautiful page makes users want to keep using it."),
            ]
        case .natural:
            return [
                ("这个按钮可以打开设置面板。", "This button opens the settings panel."),
                ("我们需要支持长文本翻译。", "We need to support long-form translation."),
            ]
        case .elegant:
            return [
                ("这个功能可以减少用户重复操作。", "This capability reduces repetitive user effort."),
                ("漂亮的页面会让用户更想继续使用。", "A refined interface encourages sustained user engagement."),
            ]
        }
    }

    public var lookupSystem: String {
        switch self {
        case .plain:
            return """
            你是「中式直译」翻译工具,把原文译为简体中文。灵魂是「Good good study, day day up」那种调性的反方向。

            核心规则:
            1. 用中文语境里能立刻听懂的「直接说出来」的方式翻,不死磕英文原意精确
            2. 偏口语、市井、大白话,不上书面腔、不上文学腔
            3. 词序、句式允许保留原文结构带来的轻微"中式翻译腔",让人能听出英文骨架
            4. 不要堆砌网络梗(如 yyds / 绝绝子 / 蚌埠住了),那些梗短命且不通用
            5. 只输出翻译结果,不解释、不带引号、不要重述输入、不要追加任何示例
            """
        case .natural:
            return """
            翻译用户给出的原文为简体中文。风格：自然、准确、日常。
            1. 保持原意准确
            2. 使用自然流畅的现代中文
            3. 只输出翻译结果,不要任何解释或额外内容
            """
        case .elegant:
            return """
            你是「典雅风」翻译工具,把原文译为有华夏古韵的中文。

            按输入自选输出格式,不要混搭:
            - 单词 / 极短词组 → 译为典雅装饰性的文言词、四字格、或不太常见的雅称
            - 一句话 / 1-3 句 → 译为通顺的文言文段,语气可参考《古文观止》《世说新语》
            - 较长段落 → 视内容自选:抒情/描写→五言或七言诗;叙事/议论→文言文段或散文诗
            - 技术性 / 事实性原文也保留古意,但不能丢失原意

            硬规则:
            1. 不要写"半文半白"的伪文言,要么真古韵,要么宁可保持简洁
            2. 诗须押韵或对仗,不要硬凑
            3. 只输出翻译结果,不附"译为五言诗:"等说明、不带引号、不要追加任何示例
            """
        }
    }

    public var lookupExamples: [(input: String, output: String)] {
        switch self {
        case .plain:
            return [
                ("Hello", "嘿"),
                ("Long time no see", "好久不见"),
                ("Take it easy", "别紧张,慢慢来"),
                ("You're killing me", "你笑死我了"),
                ("What's up", "咋了?"),
                ("It is what it is", "事就是这事儿,没法的"),
                ("Easy come easy go", "来得容易,走得也容易"),
                ("No pain, no gain", "不吃苦,没好果"),
                ("Make yourself at home", "当自己家"),
            ]
        case .natural:
            return []
        case .elegant:
            return [
                ("Wisdom", "睿哲"),
                ("Solitude", "孤怀"),
                ("Hello, friend.", "故人无恙乎?"),
                ("I miss you.", "思君如海,日夜难平。"),
                ("Time flies.", "光阴荏苒,白驹过隙。"),
                ("The morning light filled the room.", "晨光熹微,盈室如练。"),
            ]
        }
    }
}

public enum TranslationAction: CaseIterable, Sendable {
    case rewriteToEnglish
    case lookup

    public var title: String {
        switch self {
        case .rewriteToEnglish: return "用中文写英文"
        case .lookup: return "划词翻译"
        }
    }

    public var hotkeyID: UInt32 {
        switch self {
        case .rewriteToEnglish: return 1
        case .lookup: return 2
        }
    }

    public var defaultHotkey: HotkeyConfig {
        switch self {
        case .rewriteToEnglish:
            return HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
        case .lookup:
            return HotkeyConfig(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey))
        }
    }

    public var persistenceKey: String {
        switch self {
        case .rewriteToEnglish: return "rewriteToEnglish"
        case .lookup:           return "lookup"
        }
    }

    public static func from(hotkeyID: UInt32) -> TranslationAction? {
        allCases.first { $0.hotkeyID == hotkeyID }
    }
}
