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
}
