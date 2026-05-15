import AppKit
import ApplicationServices
import SwiftUI
import os.log

private let appLog = OSLog(subsystem: "com.whimsycode.dumbtrans-pro", category: "main")

@MainActor
public final class MenuBarManager {
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

    public init() {
        writeDebug("MenuBarManager init started")
        setupStatusItem()
        checkAccessibility(prompt: true)
        writeDebug("Accessibility trusted at startup: \(hasAccessibility)")
        setupHotkey()
        startAccessibilityWatcher()
        writeDebug("MenuBarManager init complete")
    }

    private func writeDebug(_ msg: String) {
        fputs("[GGS] \(msg)\n", stderr)
        os_log("%{public}@", log: appLog, type: .info, msg)
    }

    private func checkAccessibility(prompt: Bool) {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: prompt] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        // Re-prompt to also surface our app in the list if it's missing
        checkAccessibility(prompt: true)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "✦"
        }
        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()

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
            for mode in TranslationMode.allCases {
                let enabled = settingsStore.isModeEnabled(mode)
                let label = "\(mode.rawValue)  \(mode.hotkeyLabel)"
                let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                item.isEnabled = false
                if !enabled {
                    item.title = "\(mode.rawValue)  \(mode.hotkeyLabel)（已关闭）"
                }
                menu.addItem(item)
            }
            let lookup = NSMenuItem(title: "划词翻译  ⌘⇧F", action: nil, keyEquivalent: "")
            lookup.isEnabled = false
            menu.addItem(lookup)
        }

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        self.statusItem?.menu = menu
    }

    private func setupHotkey() {
        hotkeyManager.onHotkey = { [weak self] mode in
            self?.handleHotkey(mode)
        }
        hotkeyManager.onLookupHotkey = { [weak self] in
            self?.handleLookup()
        }
        let success = hotkeyManager.start()
        if !success {
            showNotification(title: "瞎翻 Pro", message: "无法注册全局快捷键。")
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

    private func handleHotkey(_ mode: TranslationMode) {
        guard !isTranslating else { return }
        guard settingsStore.hasAPIKey else {
            showNotification(title: "瞎翻 Pro", message: "请先在设置中配置 API Key")
            return
        }
        guard settingsStore.isModeEnabled(mode) else {
            writeDebug("\(mode.rawValue) mode is disabled, ignoring")
            return
        }

        isTranslating = true
        startSpinner()
        updateMenu()

        Task { @MainActor in
            defer {
                isTranslating = false
                stopSpinner()
                updateMenu()
                writeDebug("handleHotkey complete (\(mode.rawValue))")
            }

            writeDebug("Getting selected text... (mode: \(mode.rawValue))")
            guard let selectedText = await ClipboardManager.getSelectedText(),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                writeDebug("No text selected")
                showNotification(title: "瞎翻 Pro", message: "未选中任何文字")
                return
            }
            writeDebug("Selected text: \(selectedText)")

            writeDebug("Calling translate API (\(mode.rawValue))...")
            let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
            do {
                let result = try await service.translate(selectedText, mode: mode)
                writeDebug("Translation result (\(mode.rawValue)): \(result)")
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
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(store: settingsStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
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
        statusItem?.button?.title = spinnerFrames[0]
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
        statusItem?.button?.title = "✦"
    }

    private func showNotification(title: String, message: String) {
        let original = statusItem?.button?.title ?? "✦"
        statusItem?.button?.title = "✗"
        fputs("[GGS] \(title): \(message)\n", stderr)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            statusItem?.button?.title = original
        }
    }
}
