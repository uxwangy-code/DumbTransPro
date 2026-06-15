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
        Task { [licenseManager] in
            await licenseManager.revalidateIfNeeded()
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
            let warning = NSMenuItem(title: "⚠ 请先设置 API Key", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(NSMenuItem.separator())
        case .offline:
            // 无 key 但离线可用：不报警，引导而非冷拒绝
            let info = NSMenuItem(title: "离线模式 · 免费可用（配置 AI 解锁土翻/装翻、划词更准）", action: #selector(openSettings), keyEquivalent: "")
            info.image = menuSymbol("wifi.slash")
            info.target = self
            menu.addItem(info)
            menu.addItem(NSMenuItem.separator())
        case .ai:
            break
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
        switch action {
        case .rewriteToEnglish:
            handleRewriteToEnglish()
        case .lookup:
            handleLookup()
        }
    }

    @objc private func menuActionTriggered(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TranslationAction else { return }
        handleAction(action)
    }

    /// 翻译模式判定：有 key → AI；无 key 但离线引擎就绪（macOS 15+）→ 离线；否则需配置。
    private func currentMode() -> TranslationMode {
        TranslationMode.resolve(
            hasAPIKey: settingsStore.hasAPIKey,
            offlineAvailable: offlineTranslator != nil
        )
    }

    private func handleLookup() {
        let mode = currentMode()
        guard mode != .needsSetup else {
            showNotification(title: "瞎翻 Pro", message: "请先在设置中配置 API Key")
            return
        }
        // 离线免费无限，不过闸口；只有 AI 路径计额度/查 Pro。
        if mode == .ai {
            guard passesLicenseGate() else { return }
        }
        Task { @MainActor in
            guard let selectedText = await ClipboardManager.getSelectedText(),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showNotification(title: "瞎翻 Pro", message: "未选中任何文字")
                return
            }
            switch mode {
            case .ai:
                let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
                let style = settingsStore.translationStyle
                lookupPanelManager.show(
                    originalText: selectedText,
                    modelLabel: settingsStore.model,
                    onSuccess: { [weak self] in self?.licenseManager.recordTranslation() },
                    fetch: { try await service.lookup($0, style: style) }
                )
            case .offline:
                guard let engine = offlineTranslator else { return }
                lookupPanelManager.show(
                    originalText: selectedText,
                    modelLabel: "离线翻译 · 设备端",
                    fetch: { LookupResult(text: try await engine.lookupToChinese($0), didFallback: false) }
                )
            case .needsSetup:
                return
            }
        }
    }

    /// 翻译动作的 Free/Pro 闸口。被拦时给出下一步引导，不是冷拒绝。
    private func passesLicenseGate() -> Bool {
        switch licenseManager.gate(provider: settingsStore.activeProvider) {
        case .allowed:
            return true
        case .providerLocked(let provider):
            showNotification(
                title: "「\(provider.displayName)」需要 Pro",
                message: "免费版可用 \(LicenseManager.freeProviderNames)。可在设置中切换服务商，或激活 Pro 解锁全部。"
            )
            return false
        case .dailyLimitReached(let limit):
            showNotification(
                title: "今日免费额度已用完",
                message: "免费版每天 \(limit) 次翻译。升级 Pro 解锁不限次数：菜单栏 → 设置 → Pro。"
            )
            return false
        }
    }

    private func handleRewriteToEnglish() {
        guard !isTranslating else { return }
        let mode = currentMode()
        guard mode != .needsSetup else {
            showNotification(title: "瞎翻 Pro", message: "请先在设置中配置 API Key")
            return
        }
        // 离线免费无限，不过闸口；只有 AI 路径计额度/查 Pro。
        if mode == .ai {
            guard passesLicenseGate() else { return }
        }

        isTranslating = true
        startSpinner()
        scheduleLoadingToast()
        updateMenu()

        Task { @MainActor in
            let style = settingsStore.translationStyle
            defer {
                isTranslating = false
                stopSpinner()
                finishLoadingToast()
                updateMenu()
                writeDebug("handleRewriteToEnglish complete (\(mode), \(style.title))")
            }

            writeDebug("Getting selected text... (mode: \(mode), style: \(style.title))")
            guard let selectedText = await ClipboardManager.getSelectedText(),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                writeDebug("No text selected")
                showNotification(title: "瞎翻 Pro", message: "未选中任何文字")
                return
            }
            writeDebug("Selected text: \(selectedText)")

            do {
                let result: String
                switch mode {
                case .ai:
                    // AI 路径：与 v1.3 完全一致——同样的 service、style、计额度。
                    let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
                    result = try await service.translate(selectedText, style: style)
                    licenseManager.recordTranslation()
                case .offline:
                    // 离线路径：引擎出纯英文，复用与 AI 相同的 词→kebab / 句→原文 分流。
                    guard let engine = offlineTranslator else { return }
                    let english = try await engine.rewriteToEnglish(selectedText)
                    result = OfflineRewriteFormatter.format(originalInput: selectedText, english: english)
                case .needsSetup:
                    return
                }
                writeDebug("Translation result: \(result)")
                await ClipboardManager.pasteText(result)
                writeDebug("Paste complete")
            } catch {
                writeDebug("Translation error: \(error)")
                showNotification(title: "翻译失败", message: error.localizedDescription)
            }
        }
    }

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        settingsWindow?.close()
        settingsWindow = nil

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = SettingsView(store: settingsStore, hotkeyManager: hotkeyManager, license: licenseManager, offlineTranslator: offlineTranslator) { [weak window] in
            window?.close()
        }
        window.title = "瞎翻 Pro 设置"
        let hostingView = NSHostingView(rootView: view)
        window.contentView = hostingView
        // Fit the window to the SwiftUI content so new sections never get clipped
        let fitting = hostingView.fittingSize
        if fitting.height > 0 {
            window.setContentSize(fitting)
        }
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
