import Testing
@testable import DumbTransProCore

struct TranslationOutputValidatorTests {
    @Test func outputWithoutDeliverableTextIsRejected() {
        for output in ["", " \n", "...", "！？", "😀🎉", "```text\n\n```", "```\n...\n```"] {
            #expect(throws: TranslateError.self) { try TranslationOutputValidator.validate(output) }
        }
    }

    @Test func normalTextKeepsItsPunctuationEmojiAndParagraphs() throws {
        for output in ["Hi", "你好！😀", "Launch it.\n\nThen celebrate! 🎉", "项目-2026", "123"] {
            #expect(try TranslationOutputValidator.validate(output) == output)
        }
        #expect(try TranslationOutputValidator.validate("```text\nhello\n```") == "hello")
    }
}
