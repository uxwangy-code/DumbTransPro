import Testing
@testable import DumbTransProCore

struct TranslationModeTests {
    @Test func hasKeyAlwaysUsesAI() {
        #expect(TranslationMode.resolve(hasAPIKey: true, offlineAvailable: true) == .ai)
        #expect(TranslationMode.resolve(hasAPIKey: true, offlineAvailable: false) == .ai)
    }

    @Test func noKeyButOfflineAvailableUsesOffline() {
        #expect(TranslationMode.resolve(hasAPIKey: false, offlineAvailable: true) == .offline)
    }

    @Test func noKeyNoOfflineNeedsSetup() {
        #expect(TranslationMode.resolve(hasAPIKey: false, offlineAvailable: false) == .needsSetup)
    }
}

struct OfflineRewriteFormatterTests {
    @Test func termLikeInputBecomesKebab() {
        let result = OfflineRewriteFormatter.format(
            originalInput: "用户体验设计师",
            english: "User experience designer"
        )
        #expect(result == "user-experience-designer")
    }

    @Test func shortTermBecomesKebab() {
        #expect(OfflineRewriteFormatter.format(originalInput: "我的项目", english: "My Project") == "my-project")
    }

    @Test func proseInputStaysPlain() {
        let english = "This is a collection of transition effects."
        let result = OfflineRewriteFormatter.format(
            originalInput: "这是一个可以直接复制到任何项目中的过渡效果集合。",
            english: english
        )
        // 句子不应被 kebab 化
        #expect(result == english)
    }

    @Test func proseOutputIsTrimmed() {
        let result = OfflineRewriteFormatter.format(
            originalInput: "把这个功能尽快上线。",
            english: "  Launch this feature as soon as possible.  "
        )
        #expect(result == "Launch this feature as soon as possible.")
    }
}
