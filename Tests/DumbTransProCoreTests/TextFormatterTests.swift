import Testing
@testable import DumbTransProCore

struct TextFormatterTests {
    @Test func basicKebabCase() {
        #expect(TextFormatter.toKebabCase("hello world") == "hello-world")
    }

    @Test func uppercaseToLower() {
        #expect(TextFormatter.toKebabCase("Hello World") == "hello-world")
    }

    @Test func removePunctuation() {
        #expect(TextFormatter.toKebabCase("hello, world!") == "hello-world")
    }

    @Test func collapseSpaces() {
        #expect(TextFormatter.toKebabCase("hello   world") == "hello-world")
    }

    @Test func trimEdges() {
        #expect(TextFormatter.toKebabCase("  hello world  ") == "hello-world")
    }

    @Test func preserveNumbers() {
        #expect(TextFormatter.toKebabCase("project 2024") == "project-2024")
    }

    @Test func alreadyKebab() {
        #expect(TextFormatter.toKebabCase("already-kebab") == "already-kebab")
    }

    @Test func emptyString() {
        #expect(TextFormatter.toKebabCase("") == "")
    }

    @Test func chinesePassthrough() {
        #expect(TextFormatter.toKebabCase("good good study") == "good-good-study")
    }

    @Test func shortChineseTermIsTermLike() {
        #expect(TextFormatter.rewriteInputKind("未命名文件夹") == .termLike)
        #expect(TextFormatter.rewriteInputKind("漂亮") == .termLike)
    }

    @Test func sentencePunctuationIsProseLike() {
        #expect(TextFormatter.rewriteInputKind("这个页面很漂亮。") == .proseLike)
    }

    @Test func longChinesePhraseIsProseLike() {
        #expect(TextFormatter.rewriteInputKind("支持任意帧和动作分段且不硬编码九帧") == .proseLike)
    }

    @Test func sentenceMarkerCanMakeProseLike() {
        #expect(TextFormatter.rewriteInputKind("用户可以直接复制到任何项目中") == .proseLike)
    }

    @Test func chineseIdentityQuestionIsProseLikeWithoutPunctuation() {
        #expect(TextFormatter.rewriteInputKind("你是什么模型") == .proseLike)
    }

    @Test func chineseShortQuestionWithModalParticleIsProseLike() {
        #expect(TextFormatter.rewriteInputKind("你会中文吗") == .proseLike)
    }

    @Test func chineseShortTermStillTermLike() {
        #expect(TextFormatter.rewriteInputKind("用户画像") == .termLike)
    }

    @Test func singleCharQuestionMarkersInCompoundsStillTermLike() {
        #expect(TextFormatter.rewriteInputKind("哪吒") == .termLike)
        #expect(TextFormatter.rewriteInputKind("几何") == .termLike)
        #expect(TextFormatter.rewriteInputKind("哪吒传奇") == .termLike)
        #expect(TextFormatter.rewriteInputKind("几何图形") == .termLike)
    }

    @Test func commonShortChineseQuestionsAreProseLike() {
        #expect(TextFormatter.rewriteInputKind("你在哪") == .proseLike)
        #expect(TextFormatter.rewriteInputKind("哪些功能") == .proseLike)
        #expect(TextFormatter.rewriteInputKind("哪儿") == .proseLike)
        #expect(TextFormatter.rewriteInputKind("几号") == .proseLike)
    }

    @Test func singleCharQuestionMarkersInPhrasesAreProseLike() {
        #expect(TextFormatter.rewriteInputKind("哪天开会") == .proseLike)
        #expect(TextFormatter.rewriteInputKind("有几种方案") == .proseLike)
    }

    @Test func rewriteDirection_chineseTextGoesToEnglish() {
        #expect(TextFormatter.rewriteDirection(for: "你是什么模型") == .chineseToEnglish)
    }

    @Test func rewriteDirection_englishTextGoesToChinese() {
        #expect(TextFormatter.rewriteDirection(for: "What model are you?") == .foreignToChinese)
    }

    @Test func rewriteDirection_mixedChineseDominantGoesToEnglish() {
        #expect(TextFormatter.rewriteDirection(for: "请帮我 review 这个页面") == .chineseToEnglish)
    }

    @Test func repairsAIModelQuestionTerminology() {
        #expect(TextFormatter.repairForeignToChineseTranslation(
            source: "WHAT MODEL ARE YOU?",
            translation: "您是什么型号？"
        ) == "你是什么模型？")
    }

    @Test func repairsAIModelUsingQuestionTerminology() {
        #expect(TextFormatter.repairForeignToChineseTranslation(
            source: "What model are you using?",
            translation: "你使用什么型号？"
        ) == "你用的是什么模型？")
    }

    @Test func repairsAIModelBasedOnQuestionTerminology() {
        #expect(TextFormatter.repairForeignToChineseTranslation(
            source: "What model are you based on?",
            translation: "你基于什么型号？"
        ) == "你基于什么模型？")
    }

    @Test func doesNotRepairProductModelTerminology() {
        #expect(TextFormatter.repairForeignToChineseTranslation(
            source: "What model is this laptop?",
            translation: "这台笔记本是什么型号？"
        ) == "这台笔记本是什么型号？")
    }
}
