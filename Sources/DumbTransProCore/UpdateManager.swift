import AppKit
import Sparkle

@MainActor
public final class UpdateManager: NSObject, SPUUpdaterDelegate {
    public enum State: Equatable {
        case unavailable
        case idle
        case checking
        case updateAvailable(String)
        case updating
    }

    public var onStateChange: (() -> Void)?

    public private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?()
        }
    }

    public let currentVersion: String

    private let bundle: Bundle
    private var updaterController: SPUStandardUpdaterController?

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.currentVersion = Self.displayVersion(in: bundle)
        super.init()

        guard Self.hasSparkleConfiguration(in: bundle) else {
            state = .unavailable
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    public var menuTitle: String {
        switch state {
        case .unavailable:
            return "检查更新…"
        case .idle:
            return "检查更新…"
        case .checking:
            return "正在检查更新…"
        case .updateAvailable(let version):
            return "发现新版本 \(version)…"
        case .updating:
            return "正在更新…"
        }
    }

    public func configureMenuItem(_ item: NSMenuItem) {
        item.target = self
        item.action = #selector(checkForUpdates(_:))
        item.isEnabled = state != .checking && state != .updating
        item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard let updaterController else {
            showUnavailableAlert()
            return
        }

        state = .checking
        updaterController.checkForUpdates(sender)
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .updateAvailable(item.displayVersionString)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        state = .idle
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        state = .idle
    }

    public func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        state = .updating
    }

    private func showUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "更新功能尚未配置"
        alert.informativeText = "需要在发布构建中配置 Sparkle appcast 地址和 EdDSA 公钥后，才能检查并安装更新。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func hasSparkleConfiguration(in bundle: Bundle) -> Bool {
        guard let feedURLString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feedURLString) != nil else {
            return false
        }

        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }

        return !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func displayVersion(in bundle: Bundle) -> String {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.isEmpty == false ? shortVersion : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(short), .some(build)) where short != build:
            return "\(short) (\(build))"
        case let (.some(short), _):
            return short
        case let (_, .some(build)):
            return build
        default:
            return "未知版本"
        }
    }
}
