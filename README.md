# good-good-study 好好学习

> 一个 macOS 菜单栏小工具：输入中文，按快捷键，自动生成连字符英文文件名。
> 专为起不好英文名的 coding 人设计。

**例子**：`好好学习` → `⌘+Shift+T` → `good-good-study`

---

## 项目背景

起项目文件夹名是件麻烦事：想用英文显得专业，但英文不好就得打开 Google 翻译，翻完复制粘贴，还老记不住。这个工具解决的就是这个问题：**在任何输入框，选中中文，按快捷键，直接替换成英文文件名格式**。

"硬翻"风格（好好学习 → good-good-study）是有意为之——有个性，有趣，符合 vibe coding 精神。

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
- 先验证"硬翻体验"是否真的爽，再决定要不要做丝滑版（方案 A）

---

## 功能规格（MVP）

### 核心功能
- [ ] 菜单栏常驻图标（不占 Dock）
- [ ] 全局快捷键（默认 `⌘+Shift+T`，可自定义）
- [ ] 选中文字 → 调用 AI → 返回 kebab-case 英文
- [ ] 自动替换剪贴板并模拟粘贴

### 翻译风格
- **默认：硬翻模式**（逐字直译，好好学习 → good-good-study）
- Prompt 示例：
  ```
  将以下中文逐字直译成英文，用连字符连接，全小写，不要意译，不要优化。
  输入：好好学习
  输出：good-good-study
  ```

### AI 接口选型
| 接口 | 速度 | 成本 | 备注 |
|------|------|------|------|
| OpenAI GPT-4o mini | ~0.5s | 极低 | 首选 |
| Claude Haiku | ~0.5s | 极低 | 备选 |
| 本地词典（离线） | 即时 | 零 | 后续可选，覆盖常用词 |

### 非功能需求
- 响应时间 < 1 秒（用户感知流畅）
- 无需联网时有 fallback 提示
- API Key 本地存储（Keychain）

---

## 技术栈

| 层 | 技术 | 理由 |
|----|------|------|
| 语言 | Swift | macOS 原生，菜单栏 app 最合适 |
| UI | SwiftUI + NSStatusItem | 菜单栏图标标准做法 |
| 快捷键监听 | CGEventTap 或 HotKey 库 | 全局快捷键捕获 |
| 剪贴板操作 | NSPasteboard | 标准 API |
| AI 调用 | URLSession + OpenAI API | 轻量，无需第三方 SDK |
| 配置存储 | UserDefaults + Keychain | API Key 用 Keychain |

---

## 项目结构（规划）

```
good-good-study/
├── README.md               ← 本文件
├── GoodGoodStudy/
│   ├── App.swift           ← 入口
│   ├── MenuBarManager.swift ← 菜单栏图标管理
│   ├── HotkeyManager.swift  ← 全局快捷键监听
│   ├── TranslateService.swift ← AI 翻译调用
│   ├── ClipboardManager.swift ← 剪贴板读写 + 模拟粘贴
│   ├── SettingsView.swift   ← 设置界面（API Key、快捷键）
│   └── Assets.xcassets
├── GoodGoodStudy.xcodeproj
└── docs/
    └── PLAN.md             ← 本规划文件（完整版）
```

---

## 开发阶段

### 阶段一：跑通核心流程（Day 1）
- [ ] 创建 macOS 菜单栏 App 项目（Xcode）
- [ ] 实现全局快捷键监听
- [ ] 实现剪贴板读取 + 模拟粘贴
- [ ] 调通 OpenAI API，返回翻译结果

### 阶段二：打磨体验（Day 2）
- [ ] 翻译结果格式化（kebab-case，去除标点、空格）
- [ ] 加载状态（翻译中的视觉反馈，如菜单栏图标转圈）
- [ ] 错误处理（无网络、API 报错）
- [ ] 设置界面（API Key 配置）

### 阶段三：自用验证（Day 3）
- [ ] 打包为 .app
- [ ] 日常使用一周
- [ ] 收集问题，决定是否迭代为方案 A

---

## 后续迭代方向（方案 A 丝滑版）

- 监听 Finder 重命名输入框激活事件（Accessibility API）
- 输入中文后按 Tab 自动触发，无需选中
- 支持多种输出格式（kebab-case / camelCase / PascalCase）
- 本地词典 fallback（离线可用，覆盖高频词）

---

## 相关调研结论

GitHub 上无同类项目：
- 批量重命名工具（Filename-Translator）：命令行批处理，非实时，非硬翻
- 菜单栏翻译（BarTranslate、Easydict）：给人看的翻译，不是文件名格式
- **「选中中文 → 快捷键 → 替换为 kebab-case 英文」这个交互是空白**

差异化核心：**硬翻风格 + 文件名格式输出 + 极简操作路径**

---

*项目隶属 WhimsyCode 平台，启动日期：2026-04-07*
*项目路径：`/Users/thirty/myproject/good-good-study`*
