# DumbTrans Pro 瞎翻 Pro

> 一个 macOS 菜单栏小工具：输入中文，按快捷键，自动生成连字符英文文件名。
> 专为起不好英文名的 coding 人设计。

**例子**：`好好学习` → `⌘+Shift+T` → `good-good-study`

---

## 项目背景

起项目文件夹名是件麻烦事：想用英文显得专业，但英文不好就得打开 Google 翻译，翻完复制粘贴，还老记不住。这个工具解决的就是这个问题：**在任何输入框，选中中文，按快捷键，直接替换成英文文件名格式**。

"瞎翻"风格（好好学习 → good-good-study，天天向上 → day-day-up）是有意为之——有个性，有趣，符合 vibe coding 精神。所以叫 **DumbTrans Pro**：翻得又硬又 Pro。

---

## MVP 方案：方案 B（快捷键 + 剪贴板）

### 工作流程

```
用户输入中文名称（如"好好学习"）
    ↓ 选中文字
    ↓ 按 ⌘+Shift+T
    ↓ 工具调用 AI 接口翻译
    ↓ 结果格式化为 kebab-case（连字符小写）
    ↓ 自动粘贴回输入框，替换选中文字
```

### 为什么选方案 B

- 开发周期短（2-3天 vs 方案A的1-2周）
- 不依赖 Accessibility API 深度 hook，稳定性更好
- 先验证"瞎翻体验"是否真的爽，再决定要不要做丝滑版（方案 A）

---

## 功能规格（MVP）

### 核心功能
- [x] 菜单栏常驻图标（不占 Dock）
- [x] 全局快捷键（默认 `⌘+Shift+T`）
- [x] 选中文字 → 调用 AI → 返回 kebab-case 英文
- [x] 自动替换剪贴板并模拟粘贴

### 翻译风格
- **默认：瞎翻模式**（逐字直译，好好学习 → good-good-study）
- 少样本 Prompt：
  ```
  好好学习 → good good study
  天天向上 → day day up
  未命名文件夹 → unnamed file folder
  ```

### 支持的 AI 服务商
| 服务商 | 备注 |
|------|------|
| OpenAI | gpt-4o-mini |
| 智谱 GLM | glm-4-flash |
| DeepSeek | deepseek-chat |
| 月之暗面 | moonshot-v1-8k |
| 自定义 | 任意 OpenAI 兼容 API |

### 非功能需求
- 响应时间 < 1 秒（用户感知流畅）
- API Key 本地存储（Keychain）

---

## 技术栈

| 层 | 技术 | 理由 |
|----|------|------|
| 语言 | Swift 6 | macOS 原生，菜单栏 app 最合适 |
| UI | SwiftUI + NSStatusItem | 菜单栏图标标准做法 |
| 快捷键监听 | Carbon RegisterEventHotKey | 免辅助功能权限 |
| 剪贴板操作 | NSPasteboard + CGEvent | 读剪贴板 + 模拟 ⌘C/⌘V |
| AI 调用 | URLSession + OpenAI 兼容 API | 轻量，无需第三方 SDK |
| 配置存储 | UserDefaults + Keychain | API Key 用 Keychain |

---

## 项目结构

```
dumbtrans-pro/
├── README.md
├── Package.swift              ← SPM 配置
├── Sources/
│   ├── DumbTransPro/          ← 可执行入口
│   │   └── main.swift
│   └── DumbTransProCore/      ← 核心库（可测）
│       ├── MenuBarManager.swift
│       ├── HotkeyManager.swift
│       ├── ClipboardManager.swift
│       ├── TranslateService.swift
│       ├── TextFormatter.swift
│       ├── KeychainHelper.swift
│       ├── SettingsStore.swift
│       └── SettingsView.swift
├── Tests/
│   └── DumbTransProCoreTests/
├── Resources/
│   └── Info.plist
└── scripts/
    └── bundle.sh              ← 打包 .app
```

---

## 构建与运行

```bash
# 构建并打包为 .app
./scripts/bundle.sh

# 从终端启动（可看调试日志）
./build/DumbTransPro.app/Contents/MacOS/DumbTransPro

# 或双击启动
open ./build/DumbTransPro.app
```

首次运行需在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权，以便模拟 ⌘C/⌘V。

---

## 后续迭代方向（方案 A 丝滑版）

- 监听 Finder 重命名输入框激活事件（Accessibility API）
- 输入中文后按 Tab 自动触发，无需选中
- 支持多种输出格式（kebab-case / camelCase / PascalCase）
- 本地词典 fallback（离线可用，覆盖高频词）

---

*项目隶属 WhimsyCode 平台，启动日期：2026-04-07*
