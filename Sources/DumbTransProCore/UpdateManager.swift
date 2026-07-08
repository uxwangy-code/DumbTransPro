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

        public var menuTitle: String {
            switch self {
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
    }

    public struct Alert: Equatable {
        public let messageText: String
        public let informativeText: String
        public let buttonTitle: String

        public static func unavailable() -> Alert {
            Alert(
                messageText: "更新功能尚未配置",
                informativeText: "需要在发布构建中配置 Sparkle appcast 地址和 EdDSA 公钥后，才能检查并安装更新。",
                buttonTitle: "好"
            )
        }

        public static func failed(_ reason: String) -> Alert {
            Alert(
                messageText: "暂时无法检查更新",
                informativeText: "\(reason)。请检查网络后重试。",
                buttonTitle: "好"
            )
        }
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
    private var backgroundTimer: Timer?
    private var isUserInitiatedCheck = false

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
        state.menuTitle
    }

    public func configureMenuItem(_ item: NSMenuItem) {
        item.target = self
        item.action = #selector(checkForUpdates(_:))
        item.isEnabled = canCheckForUpdates
        item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
    }

    public func startBackgroundChecks(initialDelay: TimeInterval = 5, interval: TimeInterval = 86_400) {
        guard updaterController != nil else { return }
        backgroundTimer?.invalidate()

        Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForUpdateInformation()
            }
        }

        backgroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForUpdateInformation()
            }
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard let updaterController else {
            showAlert(.unavailable())
            return
        }

        isUserInitiatedCheck = true
        state = .checking
        updaterController.checkForUpdates(sender)
    }

    private var canCheckForUpdates: Bool {
        guard state != .checking && state != .updating else { return false }
        guard let updaterController else { return true }
        return updaterController.updater.canCheckForUpdates
    }

    static func customNoUpdateAlert(isUserInitiated: Bool, currentVersion: String) -> Alert? {
        // Sparkle's standard user driver already presents the user-initiated "up to date" result.
        nil
    }

    private func checkForUpdateInformation() {
        guard let updater = updaterController?.updater,
              state != .checking,
              state != .updating,
              updater.canCheckForUpdates else {
            return
        }
        isUserInitiatedCheck = false
        updater.checkForUpdateInformation()
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .updateAvailable(item.displayVersionString)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        if let alert = Self.customNoUpdateAlert(isUserInitiated: isUserInitiatedCheck, currentVersion: currentVersion) {
            showAlert(alert)
        }
        isUserInitiatedCheck = false
        state = .idle
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if isUserInitiatedCheck {
            showAlert(.failed(error.localizedDescription))
        }
        isUserInitiatedCheck = false
        state = .idle
    }

    public func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        state = .updating
    }

    private func showAlert(_ alertModel: Alert) {
        let alert = NSAlert()
        alert.messageText = alertModel.messageText
        alert.informativeText = alertModel.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: alertModel.buttonTitle)
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
