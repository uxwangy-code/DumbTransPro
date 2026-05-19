import AppKit
import DumbTransProCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        menuBarManager = MenuBarManager()
    }

    @MainActor
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(commandMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), key: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(commandMenuItem(title: "撤销", action: Selector(("undo:")), key: "z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(commandMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(commandMenuItem(title: "复制", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(commandMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(commandMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func commandMenuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = .command
        return item
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
