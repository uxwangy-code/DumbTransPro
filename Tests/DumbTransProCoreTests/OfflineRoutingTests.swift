import Testing
@testable import DumbTransProCore

struct TranslationModeTests {
    @Test func legacyPreferenceKeepsExistingAutomaticRouting() {
        #expect(TranslationMode.resolve(preference: nil, hasAPIKey: true, offlineAvailable: true) == .ai)
        #expect(TranslationMode.resolve(preference: nil, hasAPIKey: true, offlineAvailable: false) == .ai)
        #expect(TranslationMode.resolve(preference: nil, hasAPIKey: false, offlineAvailable: true) == .offline)
        #expect(TranslationMode.resolve(preference: nil, hasAPIKey: false, offlineAvailable: false) == .needsSetup)
    }

    @Test func explicitOfflineNeverFallsBackToConfiguredAI() {
        #expect(TranslationMode.resolve(
            preference: .offline,
            hasAPIKey: true,
            offlineAvailable: true
        ) == .offline)
    }

    @Test func explicitOfflineWithoutEngineDoesNotFallBackToAI() {
        #expect(TranslationMode.resolve(
            preference: .offline,
            hasAPIKey: true,
            offlineAvailable: false
        ) == .needsSetup)
    }

    @Test func explicitAIUsesAIWhenConfigured() {
        #expect(TranslationMode.resolve(
            preference: .ai,
            hasAPIKey: true,
            offlineAvailable: true
        ) == .ai)
    }

    @Test func explicitAIWithoutKeyDoesNotFallBackOffline() {
        #expect(TranslationMode.resolve(
            preference: .ai,
            hasAPIKey: false,
            offlineAvailable: true
        ) == .needsSetup)
    }
}

struct OfflineLanguagePairTests {
    @Test func englishLookupUsesExplicitEnglishSource() {
        #expect(OfflineLanguagePair.englishToChinese.sourceIdentifier == "en")
        #expect(OfflineLanguagePair.englishToChinese.targetIdentifier == "zh-Hans")
    }

    @Test func chineseRewriteUsesExplicitSimplifiedChineseSource() {
        #expect(OfflineLanguagePair.chineseToEnglish.sourceIdentifier == "zh-Hans")
        #expect(OfflineLanguagePair.chineseToEnglish.targetIdentifier == "en")
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
