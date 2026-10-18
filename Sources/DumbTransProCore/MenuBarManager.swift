import AppKit
import ApplicationServices
import Combine
import SwiftUI
import os.log

private let appLog = OSLog(subsystem: "com.whimsycode.dumbtrans-pro", category: "main")

@MainActor
public final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()
    private let settingsStore = SettingsStore()
    private let licenseManager = LicenseManager()
    private let usageTelemetry = UsageTelemetryClient()
    private let lookupPanelManager = LookupPanelManager()
    /// 离线翻译引擎，仅 macOS 15+ 创建（启动即挂隐藏 host 预热 session）；13/14 为 nil。
    private let offlineTranslator: (any OfflineTranslating)?
    private lazy var updateManager: UpdateManager = {
        let manager = UpdateManager()
        manager.onStateChange = { [weak self] in
            self?.updateMenu()
        }
        return manager
    }()
    private var settingsWindow: NSWindow?
    private var toastPanel: NSPanel?
    private var toastDismissTask: Task<Void, Never>?
    private var loadingToastDelayTask: Task<Void, Never>?
    private var loadingToastShownAt: Date?
    private var activeToastKind: ToastKind?
    private var isTranslating = false
    private var spinnerTimer: Timer?
    private let spinnerFrames: [String] = ["⣾","⣽","⣻","⢿","⡿","⣟","⣯","⣷"]
    private var spinnerIndex = 0
    private var hasAccessibility = false
    private var accessibilityWatcher: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private enum ToastKind {
        case failure
        case loading
    }

    public override init() {
        if #available(macOS 15, *) {
            offlineTranslator = AppleTranslationService()
        } else {
            offlineTranslator = nil
        }
        super.init()
        writeDebug("MenuBarManager init started")
        checkAccessibility(prompt: true)
        writeDebug("Accessibility trusted at startup: \(hasAccessibility)")
        setupStatusItem()
        setupHotkey()
        observeHotkeyChanges()
        startAccessibilityWatcher()
        updateManager.startBackgroundChecks()
        Task { [licenseManager] in
            await licenseManager.revalidateIfNeeded()
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            usageTelemetry.recordAppLaunched(licenseTier: licenseManager.tier)
            if usageTelemetry.needsConsentDecision { showTelemetryChoice() }
        }
        writeDebug("MenuBarManager init complete")
    }

    private func observeHotkeyChanges() {
        settingsStore.$hotkeys
            .dropFirst()  // skip the initial load — start(initial:) already registered those
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyHotkeyChanges()
                self.updateMenu()
            }
            .store(in: &cancellables)
    }

    private func applyHotkeyChanges() {
        for action in TranslationAction.allCases {
            _ = hotkeyManager.reregister(action: action, hotkey: settingsStore.hotkey(for: action))
        }
    }

    private func writeDebug(_ msg: String) {
        fputs("[GGS] \(msg)\n", stderr)
        os_log("%{public}@", log: appLog, type: .info, msg)
    }

    private func usageProvider(for mode: TranslationMode) -> UsageTelemetryProvider? {
        guard mode == .ai, let provider = settingsStore.activeProvider else { return nil }
        return UsageTelemetryProvider(provider: provider)
    }

    private func usageRoute(for mode: TranslationMode) -> UsageTelemetryRoute? {
        UsageTelemetryRoute(mode: mode)
    }

    @discardableResult
    private func checkAccessibility(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: prompt] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        return hasAccessibility
    }

    private func startAccessibilityWatcher() {
        accessibilityWatcher = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previous = self.hasAccessibility
                self.checkAccessibility(prompt: false)
                if self.hasAccessibility != previous {
                    self.writeDebug("Accessibility changed: \(previous) → \(self.hasAccessibility)")
                    self.updateMenu()
                }
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]

        for urlString in settingsURLs {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                break
            }
        }
        // Re-prompt only when missing, so authorized users can manage or revoke
        // the permission without seeing another authorization prompt.
        checkAccessibility(prompt: !hasAccessibility)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            applyDefaultIcon(to: button)
        }
        updateMenu()
    }

    private func applyDefaultIcon(to button: NSStatusBarButton) {
        button.title = ""
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            // Fallback if asset is missing for any reason
            button.image = nil
            button.title = "✦"
        }
    }

    private func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self
        populateMenu(menu)
        self.statusItem?.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        checkAccessibility(prompt: false)
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if !hasAccessibility {
            let warning = NSMenuItem(title: "⚠ 请授权辅助功能（点击打开设置）", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(NSMenuItem.separator())
        }

        switch currentMode() {
        case .needsSetup:
            let title = settingsStore.preferredTranslationEngine == .offline
                ? "⚠ 当前系统不支持离线翻译"
                : "⚠ 请先设置 API Key"
            let warning = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(NSMenuItem.separator())
        case .offline:
            let info = NSMenuItem(title: "当前：离线翻译 · 设备端", action: #selector(openSettings), keyEquivalent: "")
            info.image = menuSymbol("wifi.slash")
            info.target = self
            menu.addItem(info)
            menu.addItem(NSMenuItem.separator())
        case .ai:
            let provider = settingsStore.activeProvider?.displayName ?? "未选择服务"
            let info = NSMenuItem(title: "当前：AI 翻译 · \(provider)", action: #selector(openSettings), keyEquivalent: "")
            info.image = menuSymbol("sparkles")
            info.target = self
            menu.addItem(info)
            menu.addItem(NSMenuItem.separator())
        }

        if isTranslating {
            let status = NSMenuItem(title: "翻译中...", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            for action in TranslationAction.allCases {
                let item: NSMenuItem
                if let cfg = settingsStore.hotkey(for: action) {
                    item = NSMenuItem(
                        title: "\(action.title)  \(cfg.displayString)",
                        action: nil,
                        keyEquivalent: ""
                    )
                    item.isEnabled = false
                } else {
                    item = NSMenuItem(
                        title: action.title,
                        action: #selector(menuActionTriggered(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = action
                }
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let accessibility = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.attributedTitle = makeAccessibilityTitle()
        accessibility.image = menuSymbol(hasAccessibility ? "checkmark.shield" : "exclamationmark.shield")
        accessibility.target = self
        menu.addItem(accessibility)

        let settings = NSMenuItem(title: "设置（配置API；更改快捷键、翻译模式）", action: #selector(openSettings), keyEquivalent: ",")
        settings.attributedTitle = makeSettingsTitle()
        settings.image = menuSymbol("gearshape")
        settings.target = self
        menu.addItem(settings)

        // 离线模式下「今日剩余 N 次」是 AI 额度，对没配 key 的人是误导——按模式显示正确文案
        let licenseTitle: String
        if currentMode() == .offline {
            licenseTitle = licenseManager.tier == .pro ? "Pro 已激活（当前离线）" : "免费版 · 离线可用"
        } else {
            licenseTitle = licenseManager.menuTitle
        }
        let license = NSMenuItem(title: licenseTitle, action: #selector(openSettings), keyEquivalent: "")
        license.image = menuSymbol(licenseManager.tier == .pro ? "checkmark.seal" : "crown")
        license.target = self
        menu.addItem(license)

        let update = NSMenuItem(title: updateManager.menuTitle, action: nil, keyEquivalent: "")
        updateManager.configureMenuItem(update)
        menu.addItem(update)

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = menuSymbol("power")
        menu.addItem(quit)
    }

    private func menuSymbol(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        return image.withSymbolConfiguration(config)
    }

    private func makeAccessibilityTitle() -> NSAttributedString {
        let prefix: String
        let suffix: String
        if hasAccessibility {
            prefix = "辅助功能权限：已授权"
            suffix = "（点击管理/取消）"
        } else {
            prefix = "辅助功能权限：未授权"
            suffix = "（点击打开设置）"
        }
        let font = NSFont.menuFont(ofSize: 0)
        let attributed = NSMutableAttributedString(
            string: prefix,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        attributed.append(NSAttributedString(
            string: suffix,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return attributed
    }

    private func makeSettingsTitle() -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let attributed = NSMutableAttributedString(
            string: "设置",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        attributed.append(NSAttributedString(
            string: "（配置API；更改快捷键、翻译模式）",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return attributed
    }

    private func setupHotkey() {
        hotkeyManager.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        let initial: [TranslationAction: HotkeyConfig?] = Dictionary(
            uniqueKeysWithValues: TranslationAction.allCases.map { ($0, settingsStore.hotkey(for: $0)) }
        )
        let errors = hotkeyManager.start(initial: initial)
        if !errors.isEmpty {
            showNotification(title: "瞎翻 Pro", message: "部分全局快捷键注册失败,可在设置中调整。")
        }
    }

    private func handleAction(_ action: TranslationAction) {
        os_log("action.received action=%{public}@ busy=%{public}d", log: appLog, type: .debug,
               action.persistenceKey, isTranslating)
        guard !isTranslating else { return }
        isTranslating = true
        let telemetryAction = UsageTelemetryAction(action: action)
        let request = usageTelemetry.beginTranslation(action: telemetryAction, licenseTier: licenseManager.tier)
        startSpinner()
        if action == .rewriteToEnglish { scheduleLoadingToast() }
        updateMenu()
        Task { @MainActor in await runTranslation(action, request: request) }
    }

    @objc private func menuActionTriggered(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TranslationAction else { return }
        handleAction(action)
    }

    /// 未保存过新偏好时保留旧版自动路由；保存后严格使用用户选择的引擎。
    private func currentMode() -> TranslationMode {
        TranslationMode.resolve(
            preference: settingsStore.preferredTranslationEngine,
            hasAPIKey: settingsStore.hasAPIKey,
            offlineAvailable: offlineTranslator != nil
        )
    }

    private func showTranslationSetupGuidance() {
        if settingsStore.preferredTranslationEngine == .offline {
            showNotification(
                title: "当前系统不支持离线翻译",
                message: "离线翻译需要 macOS 15+。请在设置中切换到 AI 翻译，或升级 macOS 后重试。"
            )
        } else {
            showNotification(title: "瞎翻 Pro", message: "请先在设置中配置 API Key")
        }
    }

    private func finishAction() {
        isTranslating = false
        stopSpinner()
        finishLoadingToast()
        updateMenu()
    }

    private func runTranslation(_ action: TranslationAction, request: TelemetryTranslationRequest?) async {
        let mode = currentMode()
        let provider = usageProvider(for: mode)
        let route = usageRoute(for: mode)
        let style = mode == .offline ? TranslationStyle.natural : settingsStore.translationStyle
        var direction: UsageTelemetryDirection?
        func finish(_ outcome: UsageTelemetryOutcome, error: UsageTelemetryErrorKind? = nil,
                    stage: TelemetryFailureStage? = nil, delivery: TelemetryDelivery? = nil) {
            os_log("action.finished outcome=%{public}@ error=%{public}@ stage=%{public}@ delivery=%{public}@",
                   log: appLog, type: .debug, String(describing: outcome), error?.rawValue ?? "none",
                   stage?.rawValue ?? "none", delivery?.rawValue ?? "none")
            usageTelemetry.finishTranslation(request, outcome: outcome, route: route, provider: provider,
                direction: direction, style: style, errorKind: error, failureStage: stage, delivery: delivery)
            finishAction()
        }
        guard checkAccessibility(prompt: false) else {
            finish(.failed, error: .accessibilityDenied, stage: .selection)
            showNotification(title: "需要辅助功能权限", message: "请在菜单栏中打开辅助功能设置，允许瞎翻 Pro 读取所选文字和执行快捷键。")
            return
        }
        guard mode != .needsSetup else {
            finish(.failed, error: .needsSetup, stage: .setup)
            showTranslationSetupGuidance()
            return
        }
        if mode == .ai {
            switch licenseManager.gate(provider: settingsStore.activeProvider) {
            case .allowed: break
            case .providerLocked(let lockedProvider):
                finish(.blocked, error: .providerLocked)
                showNotification(title: "「\(lockedProvider.displayName)」需要 Pro", message: "免费版可用 \(LicenseManager.freeProviderNames)。在设置中切换服务商或激活 Pro。")
                return
            case .dailyLimitReached(let limit):
                finish(.blocked, error: .dailyLimitReached)
                showNotification(title: "今日免费额度已用完", message: "免费版每天 \(limit) 次 AI 翻译。菜单栏 → 设置 → Pro 可升级。")
                return
            }
        }
        let selection: ClipboardSelection
        do {
            guard let captured = try await ClipboardManager.captureSelection(),
                  !captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finish(.failed, error: .noSelection, stage: .selection)
                showNotification(title: "无法取得所选文字", message: "请重新选中文字后重试。部分应用不支持通过快捷键取词。")
                return
            }
            selection = captured
        } catch {
            if let clipboardError = error as? ClipboardOperationError {
                os_log("selection.failed reason=%{public}@", log: appLog, type: .debug,
                       String(describing: clipboardError))
            }
            finish(.failed, error: .clipboardBusy, stage: .selection)
            showNotification(title: "取词已中止", message: "焦点或剪贴板发生变化，请重新选中文字后重试。")
            return
        }
        if mode == .offline {
            os_log("engine.checking_offline_availability", log: appLog, type: .debug)
            guard let engine = offlineTranslator, await engine.availability() == .ready else {
                finish(.failed, error: .offlineLanguageMissing, stage: .setup)
                showOfflineSetupGuidance()
                return
            }
        }
        let selectedText = selection.text
        os_log("engine.start action=%{public}@", log: appLog, type: .debug, action.persistenceKey)
        if action == .lookup {
            direction = .foreignToChinese
            let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
            let engine = offlineTranslator
            lookupPanelManager.show(
                originalText: selectedText,
                modelLabel: mode == .ai ? settingsStore.model : "离线翻译 · 设备端",
                onSuccess: { [weak self] in
                    guard let self else { return }
                    if mode == .ai { self.licenseManager.recordTranslation() }
                    finish(.succeeded, delivery: .panelShown)
                },
                onFailure: { error in finish(.failed, error: UsageTelemetryErrorKind(error: error), stage: .engine) },
                onCancelled: { finish(.cancelled) },
                fetch: { text in
                    if mode == .ai { return try await service.lookup(text, style: style) }
                    guard let engine else { throw TranslateError.invalidResponse }
                    let output = try await engine.lookupToChinese(text)
                    let validOutput = try TranslationOutputValidator.validate(output)
                    let result = TextFormatter.repairForeignToChineseTranslation(source: text, translation: validOutput)
                    return LookupResult(text: try TranslationOutputValidator.validate(result), didFallback: false)
                }
            )
            return
        }
        let rewriteDirection = TextFormatter.rewriteDirection(for: selectedText)
        direction = UsageTelemetryDirection(direction: rewriteDirection)
        do {
            let output: String
            switch mode {
            case .ai:
                let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
                switch rewriteDirection {
                case .chineseToEnglish: output = try await service.translate(selectedText, style: style)
                case .foreignToChinese: output = try await service.translateToChinese(selectedText, style: style)
                }
            case .offline:
                guard let engine = offlineTranslator else { throw TranslateError.invalidResponse }
                switch rewriteDirection {
                case .chineseToEnglish:
                    output = try OfflineRewriteFormatter.format(originalInput: selectedText, english: await engine.rewriteToEnglish(selectedText))
                case .foreignToChinese:
                    let raw = try await engine.lookupToChinese(selectedText)
                    let valid = try TranslationOutputValidator.validate(raw)
                    output = TextFormatter.repairForeignToChineseTranslation(source: selectedText, translation: valid)
                }
            case .needsSetup: throw TranslateError.noAPIKey
            }
            let result = try TranslationOutputValidator.validate(output)
            os_log("engine.succeeded unchanged=%{public}d", log: appLog, type: .debug, result == selectedText)
            if mode == .ai { licenseManager.recordTranslation() }
            let pasteOutcome = try? await ClipboardManager.pasteText(result, replacing: selection.target)
            if pasteOutcome == .pasteRequested {
                finish(.succeeded, delivery: .pasteRequested)
            } else {
                lookupPanelManager.showResult(originalText: selectedText, translation: result,
                    label: "选区已变化，请复制译文后粘贴")
                finish(.succeeded, delivery: .manualCopyAvailable)
            }
        } catch {
            finish(.failed, error: UsageTelemetryErrorKind(error: error), stage: .engine)
            showNotification(title: "翻译失败", message: error.localizedDescription)
        }
    }

    private func showOfflineSetupGuidance() {
        showNotification(title: "离线翻译需要语言包", message: "已打开翻译设置。请下载中文和英文语言包后重试。")
        showSettings(section: .translation)
    }

    private func showTelemetryChoice() {
        let alert = NSAlert()
        alert.messageText = "帮助改进瞎翻 Pro"
        alert.informativeText = "允许发送使用次数、成功或失败情况和随机安装编号，用于了解使用频率和改进稳定性。不会收集翻译内容、剪贴板或密钥。你可以随时关闭，翻译功能不受影响。"
        alert.addButton(withTitle: "允许使用统计")
        alert.addButton(withTitle: "暂不开启")
        alert.addButton(withTitle: "隐私政策")
        switch alert.runModal() {
        case .alertFirstButtonReturn: usageTelemetry.setConsent(true)
        case .alertSecondButtonReturn: usageTelemetry.setConsent(false)
        default:
            NSWorkspace.shared.open(URL(string: "https://uxwangy-code.github.io/DumbTransPro/privacy.html")!)
            showSettings(section: .feedbackAbout)
        }
    }

    @objc private func openSettings() { showSettings(section: .aiService) }

    private func showSettings(section: SettingsPanelSection) {
        if section == .aiService, let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        settingsWindow?.close()
        settingsWindow = nil

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = SettingsView(store: settingsStore, hotkeyManager: hotkeyManager, license: licenseManager, offlineTranslator: offlineTranslator, telemetry: usageTelemetry, initialSection: section) { [weak window] in
            window?.close()
        }
        window.title = "瞎翻 Pro 设置"
        let hostingView = NSHostingView(rootView: view)
        window.contentView = hostingView
        window.minSize = NSSize(width: 720, height: 500)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func startSpinner() {
        spinnerIndex = 0
        if let button = statusItem?.button {
            button.image = nil
            button.title = spinnerFrames[0]
        }
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.spinnerIndex = (self.spinnerIndex + 1) % self.spinnerFrames.count
                self.statusItem?.button?.title = self.spinnerFrames[self.spinnerIndex]
            }
        }
    }

    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        if let button = statusItem?.button {
            applyDefaultIcon(to: button)
        }
    }

    private func showNotification(title: String, message: String) {
        fputs("[GGS] \(title): \(message)\n", stderr)
        cancelLoadingToast(closeImmediately: true)
        flashStatusFailure()
        showFailureToast(title: title, message: message)
    }

    private func flashStatusFailure() {
        guard let button = statusItem?.button else { return }
        button.image = nil
        button.title = "✗"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let button = self.statusItem?.button else { return }
            if !self.isTranslating {
                self.applyDefaultIcon(to: button)
            }
        }
    }

    private func showFailureToast(title: String, message: String) {
        toastDismissTask?.cancel()

        let toastView = FailureToastView(title: title, message: message)
        let panel = showToastPanel(rootView: toastView, width: 320, minHeight: 76, maxHeight: 150)
        activeToastKind = .failure

        toastDismissTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(2400))
            guard !Task.isCancelled, let self, let panel, self.toastPanel === panel else { return }
            panel.close()
            self.toastPanel = nil
            self.toastDismissTask = nil
            self.activeToastKind = nil
        }
    }

    private func scheduleLoadingToast() {
        cancelLoadingToast(closeImmediately: true)
        loadingToastDelayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.isTranslating else { return }
            self.showLoadingToast()
        }
    }

    private func showLoadingToast() {
        toastDismissTask?.cancel()
        let toastView = LoadingToastView()
        _ = showToastPanel(rootView: toastView, width: 196, minHeight: 52, maxHeight: 72)
        activeToastKind = .loading
        loadingToastShownAt = Date()
    }

    private func finishLoadingToast() {
        loadingToastDelayTask?.cancel()
        loadingToastDelayTask = nil

        guard activeToastKind == .loading else { return }
        let elapsed = loadingToastShownAt.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = max(0, 1.0 - elapsed)
        if remaining <= 0 {
            closeLoadingToast()
        } else {
            toastDismissTask?.cancel()
            toastDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                guard !Task.isCancelled else { return }
                self?.closeLoadingToast()
            }
        }
    }

    private func cancelLoadingToast(closeImmediately: Bool) {
        loadingToastDelayTask?.cancel()
        loadingToastDelayTask = nil
        loadingToastShownAt = nil
        guard closeImmediately, activeToastKind == .loading else { return }
        toastDismissTask?.cancel()
        closeLoadingToast()
    }

    private func closeLoadingToast() {
        guard activeToastKind == .loading else { return }
        toastPanel?.close()
        toastPanel = nil
        toastDismissTask = nil
        activeToastKind = nil
        loadingToastShownAt = nil
    }

    private func showToastPanel<Content: View>(
        rootView: Content,
        width: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> NSPanel {
        toastPanel?.close()

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        let fittingSize = hostingView.fittingSize
        let panelSize = NSSize(width: width, height: min(max(fittingSize.height, minHeight), maxHeight))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
        panel.setFrameOrigin(toastOrigin(for: panelSize))
        panel.orderFront(nil)
        toastPanel = panel
        return panel
    }

    private func toastOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 16

        let preferredX = mouse.x + margin
        let preferredY = mouse.y - size.height - margin
        let maxX = visibleFrame.maxX - size.width - margin
        let minX = visibleFrame.minX + margin
        let maxY = visibleFrame.maxY - size.height - margin
        let minY = visibleFrame.minY + margin

        return NSPoint(
            x: min(max(preferredX, minX), maxX),
            y: min(max(preferredY, minY), maxY)
        )
    }
}

private struct FailureToastView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(ToastBackground())
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        )
    }
}

private struct LoadingToastView: View {
    private let frames: [String] = ["⣾","⣽","⣻","⢿","⡿","⣟","⣯","⣷"]

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 0.1)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate * 10) % frames.count
                Text(frames[index])
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
            }
            Text("翻译中，请稍等...")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 212, alignment: .leading)
        .background(ToastBackground())
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        )
    }

}

private struct ToastBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Color.black.opacity(0.7)
        }
    }
}
