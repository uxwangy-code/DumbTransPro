# good-good-study 设计文档

**日期**：2026-04-08
**状态**：已确认

## 定位

macOS 菜单栏工具：选中中文 → 快捷键 → 替换为 kebab-case 英文文件名。硬翻风格（好好学习 → good-good-study）。

## 架构

SPM 可执行目标 + shell 脚本打包为 .app bundle。不依赖 Xcode。

### 模块

| 文件 | 职责 |
|------|------|
| `App.swift` | NSApplication 入口，无 Dock 图标 |
| `MenuBarManager.swift` | NSStatusItem 菜单栏图标 + 下拉菜单 |
| `HotkeyManager.swift` | CGEventTap 全局快捷键（默认 ⌘+Shift+T） |
| `TranslateService.swift` | OpenAI API 硬翻调用 |
| `ClipboardManager.swift` | NSPasteboard 读写 + CGEvent 模拟粘贴 |
| `SettingsView.swift` | SwiftUI 设置窗口（API Key、快捷键配置） |
| `KeychainHelper.swift` | Keychain 存取 API Key |

### 数据流

```
用户选中中文文字
  → ⌘+Shift+T 触发 HotkeyManager
  → ClipboardManager 模拟 ⌘+C 复制选中文字
  → TranslateService 调用 OpenAI API 硬翻
  → 结果格式化为 kebab-case
  → ClipboardManager 写入剪贴板
  → ClipboardManager 模拟 ⌘+V 粘贴替换
```

### 构建

- `Package.swift`：定义可执行目标，依赖 AppKit/SwiftUI
- `scripts/bundle.sh`：编译 + 打包为 .app bundle
- `Resources/Info.plist`：LSUIElement = true
- `Resources/GoodGoodStudy.entitlements`：辅助功能权限

### AI 接口

- 首选：OpenAI GPT-4o mini
- Prompt：逐字直译，连字符连接，全小写，不意译
- 响应时间目标 < 1 秒
- 无网络时提示用户

### 权限

- 辅助功能（Accessibility）：CGEventTap 全局快捷键监听
- 网络：API 调用

### 错误处理

- API 失败：菜单栏图标闪烁 + 通知
- 无网络：提示「无网络连接」
- 非中文输入：原样返回不处理

### 存储

- API Key：macOS Keychain
- 用户偏好（快捷键等）：UserDefaults
