import Foundation
import Testing

struct WebsitePricingTests {
    @Test func homepageShowsSeparateDomesticAndOverseasPurchaseChoices() throws {
        let html = try homepageHTML()

        #expect(html.contains("国内用户：微信/支付宝购买"))
        #expect(html.contains("海外用户：Gumroad 购买"))
        #expect(html.contains("千寻虚拟卡购买页准备中"))
        #expect(html.contains("早鸟 ¥9.9"))
        #expect(html.contains("正式 ¥39"))
        #expect(html.contains("Early bird $1.49"))
        #expect(html.contains("Standard $5.99"))
        #expect(!html.contains("$6.99"))
        #expect(!html.contains("$14.99"))
        #expect(!html.contains("面包多"))
        #expect(!html.localizedCaseInsensitiveContains("Mianbaoduo"))
    }

    @Test func homepageDoesNotPromiseAutomaticRegionDetection() throws {
        let html = try homepageHTML()

        #expect(html.contains("自己选择购买渠道"))
        #expect(html.contains("Choose the checkout that fits you"))
        #expect(!html.localizedCaseInsensitiveContains("auto-detect"))
        #expect(!html.contains("自动判断地区"))
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
}
