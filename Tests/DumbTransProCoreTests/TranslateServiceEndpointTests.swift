import Foundation
import Testing
@testable import DumbTransProCore

struct TranslateServiceEndpointTests {
    @Test func appendsPathToBaseURL() {
        #expect(
            TranslateService.endpointURL(baseURL: "https://api.openai.com/v1")?.absoluteString
            == "https://api.openai.com/v1/chat/completions"
        )
    }

    @Test func toleratesTrailingSlashes() {
        #expect(
            TranslateService.endpointURL(baseURL: "https://api.openai.com/v1//")?.absoluteString
            == "https://api.openai.com/v1/chat/completions"
        )
    }

    @Test func trimsWhitespace() {
        #expect(
            TranslateService.endpointURL(baseURL: "  https://api.deepseek.com/v1 ")?.absoluteString
            == "https://api.deepseek.com/v1/chat/completions"
        )
    }

    @Test func emptyInputReturnsNilInsteadOfCrashing() {
        // 新版 Foundation 的 URL(string:) 会自动百分号转义非法字符,
        // 所以只有空输入才返回 nil —— 但无论输入什么都不再 force-unwrap 崩溃
        #expect(TranslateService.endpointURL(baseURL: "") == nil)
        #expect(TranslateService.endpointURL(baseURL: "   ") == nil)
        #expect(TranslateService.endpointURL(baseURL: "///") == nil)
    }
}
