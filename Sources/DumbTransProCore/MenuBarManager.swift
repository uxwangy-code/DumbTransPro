import AppKit
import ApplicationServices
import SwiftUI
import os.log

private let appLog = OSLog(subsystem: "com.whimsycode.dumbtrans-pro", category: "main")

@MainActor
public final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()
    private let settingsStore = SettingsStore()
    private let lookupPanelManager = LookupPanelManager()
    private var settingsWindow: NSWindow?
    private var isTranslating = false
    private var spinnerTimer: Timer?
    private let spinnerFrames: [String] = ["⣾","⣽","⣻","⢿","⡿","⣟","⣯","⣷"]
    private var spinnerIndex = 0
    private var hasAccessibility = false
    private var accessibilityWatcher: Timer?

    public override init() {
        super.init()
        writeDebug("MenuBarManager init started")
        checkAccessibility(prompt: true)
        writeDebug("Accessibility trusted at startup: \(hasAccessibility)")
        setupStatusItem()
        setupHotkey()
        startAccessibilityWatcher()
        writeDebug("MenuBarManager init complete")
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

        if !settingsStore.hasAPIKey {
            let warning = NSMenuItem(title: "⚠ 请先设置 API Key", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(NSMenuItem.separator())
        }

        if isTranslating {
            let status = NSMenuItem(title: "翻译中...", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            for action in TranslationAction.allCases {
                let item = NSMenuItem(title: "\(action.title)  \(action.hotkeyLabel)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let accessibilityTitle = hasAccessibility
            ? "辅助功能权限：已授权（点击管理/取消）"
            : "辅助功能权限：未授权（点击打开设置）"
        let accessibility = NSMenuItem(title: accessibilityTitle, action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(accessibility)

        let settings = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func setupHotkey() {
        hotkeyManager.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        let success = hotkeyManager.start()
        if !success {
            showNotification(title: "瞎翻 Pro", message: "无法注册全局快捷键。")
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

    private func handleLookup() {
        guard settingsStore.hasAPIKey else {
            showNotification(title: "瞎翻 Pro", message: "请先在设置中配置 API Key")
            return
        }
        Task { @MainActor in
            guard let selectedText = await ClipboardManager.getSelectedText(),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showNotification(title: "瞎翻 Pro", message: "未选中任何文字")
                return
            }
            lookupPanelManager.show(originalText: selectedText, settingsStore: settingsStore)
        }
    }

    private func handleRewriteToEnglish() {
        guard !isTranslating else { return }
        guard settingsStore.hasAPIKey else {
            showNotification(title: "瞎翻 Pro", message: "请先在设置中配置 API Key")
            return
        }

        isTranslating = true
        startSpinner()
        updateMenu()

        Task { @MainActor in
            let style = settingsStore.translationStyle
            defer {
                isTranslating = false
                stopSpinner()
                updateMenu()
                writeDebug("handleRewriteToEnglish complete (\(style.title))")
            }

            writeDebug("Getting selected text... (style: \(style.title))")
            guard let selectedText = await ClipboardManager.getSelectedText(),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                writeDebug("No text selected")
                showNotification(title: "瞎翻 Pro", message: "未选中任何文字")
                return
            }
            writeDebug("Selected text: \(selectedText)")

            writeDebug("Calling translate API (\(style.title))...")
            let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
            do {
                let result = try await service.translate(selectedText, style: style)
                writeDebug("Translation result (\(style.title)): \(result)")
                writeDebug("Pasting result...")
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = SettingsView(store: settingsStore) { [weak window] in
            window?.close()
        }
        window.title = "瞎翻 Pro 设置"
        window.contentView = NSHostingView(rootView: view)
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
        guard let button = statusItem?.button else { return }
        let savedImage = button.image
        let savedTitle = button.title
        button.image = nil
        button.title = "✗"
        fputs("[GGS] \(title): \(message)\n", stderr)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let button = self.statusItem?.button else { return }
            if savedImage != nil {
                self.applyDefaultIcon(to: button)
            } else {
                button.title = savedTitle
            }
        }
    }
}
