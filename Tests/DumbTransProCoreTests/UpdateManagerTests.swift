import Testing
@testable import DumbTransProCore

@MainActor
struct UpdateManagerTests {
    @Test func stateTitlesReflectCheckingAndAvailableUpdates() {
        #expect(UpdateManager.State.idle.menuTitle == "检查更新…")
        #expect(UpdateManager.State.checking.menuTitle == "正在检查更新…")
        #expect(UpdateManager.State.updateAvailable("1.6.0").menuTitle == "发现新版本 1.6.0…")
        #expect(UpdateManager.State.updating.menuTitle == "正在更新…")
    }

    @Test func upToDateAlertCopyMatchesCurrentVersionPrompt() {
        let alert = UpdateManager.Alert.upToDate(currentVersion: "1.5.0 (150)")

        #expect(alert.messageText == "当前已是最新版本")
        #expect(alert.informativeText == "当前版本：1.5.0 (150)")
        #expect(alert.buttonTitle == "好")
    }
}
