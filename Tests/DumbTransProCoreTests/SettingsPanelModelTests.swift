import Testing
import Foundation
@testable import DumbTransProCore

struct SettingsPanelModelTests {
    @Test func settingsSectionsMatchOptimizedPanelInformationArchitecture() {
        #expect(SettingsPanelSection.allCases.map(\.title) == [
            "AI 服务",
            "翻译设置",
            "Pro",
            "反馈与关于",
        ])
        #expect(SettingsPanelSection.allCases.map(\.id) == [
            "ai-service",
            "translation",
            "pro",
            "feedback-about",
        ])
        #expect(SettingsPanelSection.feedbackAbout.summary == "邮件反馈、匿名使用数据、版本、官网、GitHub、隐私")
    }

    @Test func sidebarItemStateMarksSelectedSection() {
        let selected = SettingsPanelSidebarItemState(section: .translation, selectedSection: .translation)
        let unselected = SettingsPanelSidebarItemState(section: .pro, selectedSection: .translation)

        #expect(selected.isSelected)
        #expect(selected.accessibilityLabel == "翻译设置")
        #expect(selected.accessibilityValue == "已选中")
        #expect(!unselected.isSelected)
        #expect(unselected.accessibilityLabel == "Pro")
        #expect(unselected.accessibilityValue == nil)
    }

    @Test func feedbackMailURLPrefillsRecipientSubjectAndBasicInformation() throws {
        let url = SettingsFeedbackMail.url(
            context: SettingsFeedbackContext(
                appVersion: "1.4.0 (120)",
                macOSVersion: "macOS 15.5",
                activeProviderName: "OpenAI",
                licenseStatus: "Free"
            )
        )

        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:hi@whimsycode.com"))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(queryItems["subject"] == "瞎翻 Pro 反馈")

        let body = try #require(queryItems["body"])
        #expect(body.contains("App Version: 1.4.0 (120)"))
        #expect(body.contains("macOS: macOS 15.5"))
        #expect(body.contains("Provider: OpenAI"))
        #expect(body.contains("License: Free"))
    }
}
