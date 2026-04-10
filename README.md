# 瞎翻 Pro · DumbTrans Pro

> 选中中文，按一下快捷键，立刻变成 kebab-case 英文文件名。
> 专治"想起个英文项目名但憋不出来"。

```
好好学习   →  ⌃⌥⌘T  →  good-good-study
天天向上   →  ⌃⌥⌘T  →  day-day-up
未命名文件夹 →  ⌃⌥⌘T  →  unnamed-file-folder
```

一个常驻 macOS 菜单栏的小工具。不抢焦点、不占 Dock，任何输入框都能用。

---

## 为什么做这个

起项目名这件事，挡住了太多次"就写两行玩一下"的冲动：

- 打开浏览器 → 开翻译 → 复制中文 → 粘贴 → 复制结果 → 切回 Finder → 粘贴 → 再把空格改成 `-`
- 或者干脆随便敲个 `test2`、`new_project_final_v3`，三个月后自己都找不到

这个工具把那套流程压缩成一个快捷键。翻译风格刻意保留"瞎翻"的直译感（好好学习 = good-good-study），一方面省事，另一方面——更有 vibe。

---

## 功能

- 🎯 **全局快捷键** `⌃⌥⌘T`（Control + Option + Command + T），任何 app 的任何输入框都能用
- ✂️ **自动流程**：读取选中文字 → 调 AI 翻译 → 格式化为 kebab-case → 自动粘贴回去
- 🍱 **多家 AI 服务商**：OpenAI、智谱 GLM、DeepSeek、月之暗面，以及任意 OpenAI 兼容 endpoint
- 🔐 **API Key 存 Keychain**，不落盘在任何明文配置里
- 👻 **纯菜单栏常驻**，不占 Dock 格子
- ⚡ **原生 Swift**，冷启动快，内存占用低

---

## 安装

目前需要从源码构建（后续会提供 Release 里的预编译 `.app`）：

```bash
git clone https://github.com/uxwangy-code/DumbTransPro.git
cd DumbTransPro
./scripts/bundle.sh
open build/DumbTransPro.app
```

依赖：macOS 13+、Xcode Command Line Tools（`xcode-select --install`）。

### 首次启动授权

因为要模拟 `⌘C`/`⌘V` 把结果贴回原输入框，需要授予辅助功能权限：

1. 第一次按快捷键时 macOS 会弹窗，点 **打开系统设置**
2. 进入 **隐私与安全性 → 辅助功能**
3. 开启 `DumbTransPro` 的开关

如果没弹窗，就手动去同样的路径，点 `+` 添加 `build/DumbTransPro.app`。

---

## 配置

点击菜单栏的 `好` 图标 → **设置**，填入 API Key：

| 服务商 | 默认模型 | 申请地址 |
|--------|---------|---------|
| 智谱 GLM | `glm-4-flash`（免费额度够用） | https://open.bigmodel.cn |
| OpenAI | `gpt-4o-mini` | https://platform.openai.com |
| DeepSeek | `deepseek-chat` | https://platform.deepseek.com |
| 月之暗面 | `moonshot-v1-8k` | https://platform.moonshot.cn |
| 自定义 | 任意 OpenAI 兼容 API | — |

> 推荐新手从 **智谱 GLM** 开始，注册即送额度，`glm-4-flash` 本身也是免费的。

---

## 使用

在 **任何** 输入框里（Finder 重命名、编辑器、浏览器地址栏、终端……）：

1. 选中中文
2. 按 `⌃⌥⌘T`
3. 等菜单栏图标从 `好` 变成 `⏳` 再变回 `好`（一般 500ms 内）
4. 选中的中文就被替换成了 kebab-case 英文

就这样。

---

## 从源码构建

```bash
# 运行测试
swift test

# 开发期直接跑二进制（日志打到 stderr）
swift run DumbTransPro

# 构建可分发的 .app bundle
./scripts/bundle.sh
```

技术栈：Swift 6 · SwiftUI · Carbon RegisterEventHotKey · NSPasteboard + CGEvent · URLSession。没有任何第三方依赖，`Package.swift` 清清爽爽。

---

## Roadmap

- [ ] GitHub Releases 提供签名好的 `.app` 下载，免去源码构建
- [ ] 支持更多输出格式：`camelCase` / `PascalCase` / `snake_case`
- [ ] 可自定义快捷键
- [ ] 可自定义翻译 Prompt / 少样本示例
- [ ] 历史记录 + 一键复用

欢迎开 issue 提想法。

---

## License

[MIT](./LICENSE) © 2026 Thirty
