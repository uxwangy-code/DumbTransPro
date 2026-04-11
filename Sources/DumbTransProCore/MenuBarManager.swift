import AppKit
import SwiftUI

@MainActor
public final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()
    private let settingsStore = SettingsStore()
    private var settingsWindow: NSWindow?
    private var isTranslating = false
    private var spinnerTimer: Timer?
    private let spinnerFrames: [String] = ["⣾","⣽","⣻","⢿","⡿","⣟","⣯","⣷"]
    private var spinnerIndex = 0

    public init() {
        writeDebug("MenuBarManager init started")
        setupStatusItem()
        setupHotkey()
        writeDebug("MenuBarManager init complete")
    }

    private func writeDebug(_ msg: String) {
        fputs("[GGS] \(msg)\n", stderr)
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
        let success = hotkeyManager.start()
        if !success {
            showNotification(title: "瞎翻 Pro", message: "无法注册全局快捷键。")
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
