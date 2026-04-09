import AppKit
import SwiftUI

@MainActor
public final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()
    private let settingsStore = SettingsStore()
    private var settingsWindow: NSWindow?
    private var isTranslating = false

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
            button.title = "好"
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

        let statusTitle = isTranslating ? "翻译中..." : "快捷键: ⌘+Shift+T"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        self.statusItem?.menu = menu
    }

    private func setupHotkey() {
        hotkeyManager.onHotkey = { [weak self] in
            self?.handleHotkey()
        }
        let success = hotkeyManager.start()
        if !success {
            showNotification(title: "good-good-study", message: "无法注册全局快捷键。")
        }
    }

    private func handleHotkey() {
        guard !isTranslating else { return }
        guard settingsStore.hasAPIKey else {
            showNotification(title: "good-good-study", message: "请先在设置中配置 API Key")
            return
        }

        isTranslating = true
        statusItem?.button?.title = "⏳"
        updateMenu()

        Task { @MainActor in
            defer {
                isTranslating = false
                statusItem?.button?.title = "好"
                updateMenu()
            }

            // Get selected text
            guard let selectedText = await ClipboardManager.getSelectedText(),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showNotification(title: "good-good-study", message: "未选中任何文字")
                return
            }

            // Translate
            let service = TranslateService(apiKey: settingsStore.apiKey, baseURL: settingsStore.baseURL, model: settingsStore.model)
            do {
                let result = try await service.translate(selectedText)
                await ClipboardManager.pasteText(result)
            } catch {
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "good-good-study 设置"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func showNotification(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
