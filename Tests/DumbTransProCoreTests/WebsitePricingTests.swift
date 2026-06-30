import Foundation
import Testing

struct WebsitePricingTests {
    @Test func homepageShowsSeparateDomesticAndOverseasPurchaseChoices() throws {
        let html = try homepageHTML()

        #expect(html.contains("国内用户：微信/支付宝购买"))
        #expect(html.contains("海外用户：Gumroad 购买"))
        #expect(html.contains("千寻虚拟卡购买页已开通"))
        #expect(html.contains("https://www.qianxun1688.com/details/2EB3C4E0"))
        #expect(html.contains("去千寻购买"))
        #expect(html.contains("国内 Pro ¥9.9"))
        #expect(html.contains("海外 Gumroad $1.49"))
        #expect(html.contains("https://whimsycode.gumroad.com/l/dumbtranspro"))
        #expect(html.contains("空状态插画"))
        #expect(html.contains("Empty state illustration"))
        #expect(html.contains("progressive disclosure"))
        #expect(html.contains("渐进式展示"))
        #expect(html.contains("早鸟 ¥9.9"))
        #expect(html.contains("正式 ¥39"))
        #expect(html.contains("Early bird $1.49"))
        #expect(html.contains("Standard $5.99"))
        #expect(!html.contains("$6.99"))
        #expect(!html.contains("$14.99"))
        #expect(!html.contains("面包多"))
        #expect(!html.localizedCaseInsensitiveContains("Mianbaoduo"))
        #expect(!html.contains("预约国内购买"))
        #expect(!html.contains("mailto:hi@whimsycode.com?subject="))
        #expect(!html.contains("选择 Pro 购买渠道"))
        #expect(!html.contains("Choose Pro checkout"))
        #expect(!html.contains("你是什么模型"))
        #expect(!html.contains("What model are you"))
        #expect(!html.contains("Long time no see"))
        #expect(!html.contains("好久不见"))
    }

    @Test func homepageDoesNotPromiseAutomaticRegionDetection() throws {
        let html = try homepageHTML()

        #expect(html.contains("自己选择购买渠道"))
        #expect(html.contains("Choose the checkout that fits you"))
        #expect(!html.localizedCaseInsensitiveContains("auto-detect"))
        #expect(!html.contains("自动判断地区"))
    }

    @Test func releaseScriptEmbedsProductionLicenseURLsByDefault() throws {
        let script = try releaseUpdateScript()

        #expect(script.contains("LICENSE_PURCHASE_URL=\"${DUMBTRANS_LICENSE_PURCHASE_URL:-https://uxwangy-code.github.io/DumbTransPro/#pricing}\""))
        #expect(script.contains("LICENSE_VERIFY_URL=\"${DUMBTRANS_LICENSE_VERIFY_URL:-https://license.whimsycode.com/api/licenses/verify}\""))
        #expect(script.contains("DUMBTRANS_LICENSE_PURCHASE_URL=\"$LICENSE_PURCHASE_URL\""))
        #expect(script.contains("DUMBTRANS_LICENSE_VERIFY_URL=\"$LICENSE_VERIFY_URL\""))
        #expect(!script.contains("DUMBTRANS_LICENSE_VERIFY_URL=\"${DUMBTRANS_LICENSE_VERIFY_URL:-}\""))
    }

    @Test func releaseScriptEmbedsProductionTelemetryURLByDefault() throws {
        let script = try releaseUpdateScript()

        #expect(script.contains("USAGE_TELEMETRY_URL=\"${DUMBTRANS_USAGE_TELEMETRY_URL:-https://dumbtranspro-telemetry.whimsycode.workers.dev/events}\""))
        #expect(script.contains("DUMBTRANS_USAGE_TELEMETRY_URL=\"$USAGE_TELEMETRY_URL\""))
        #expect(!script.contains("DUMBTRANS_USAGE_TELEMETRY_URL=\"${DUMBTRANS_USAGE_TELEMETRY_URL:-}\""))
    }

    @Test func releaseScriptChecksBuiltArtifactConfiguration() throws {
        let script = try releaseUpdateScript()

        #expect(script.contains("scripts/check-release-artifact.sh"))
        #expect(script.contains("DUMBTRANS_EXPECTED_USAGE_TELEMETRY_URL=\"$USAGE_TELEMETRY_URL\""))
        #expect(script.contains("DUMBTRANS_EXPECTED_LICENSE_PURCHASE_URL=\"$LICENSE_PURCHASE_URL\""))
        #expect(script.contains("DUMBTRANS_EXPECTED_LICENSE_VERIFY_URL=\"$LICENSE_VERIFY_URL\""))
    }

    private func homepageHTML() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let indexURL = repoRoot.appendingPathComponent("docs/index.html")
        return try String(contentsOf: indexURL, encoding: .utf8)
    }

    private func releaseUpdateScript() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repoRoot.appendingPathComponent("scripts/release-update.sh")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }
}
