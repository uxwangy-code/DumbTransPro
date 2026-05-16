# 瞎翻 Pro · DumbTrans Pro

> 选中文字 + 一个快捷键 = 翻译。常驻 macOS 菜单栏的小工具，不抢焦点、不占 Dock。

```
好好学习         →  ⌘⇧R  →  study-hard          （正翻 = 默认自然风格）
好好学习         →  ⌘⇧R  →  good-good-study      （土翻 = 中式直译,差生专用）
select english   →  ⌘⇧F  →  浮动面板给出中文译文   （划词翻译）
```

---

## 为什么做这个

起项目名挡住了太多次"就写两行玩一下"的冲动：

- 打开浏览器 → 开翻译 → 复制中文 → 粘贴 → 复制结果 → 切回 Finder → 粘贴 → 再把空格改成 `-`
- 或者干脆随便敲个 `test2`、`new_project_final_v3`，三个月后自己都找不到

后来发现这套快捷键还能用在另一个高频场景：**在英文设计平台搜素材**——上 Dribbble / Behance / Pinterest 这类网站找参考时，脑子里只有中文关键词，想不起来对应英文怎么写。在搜索框里输入中文 → `⌘⇧R` → 直接翻译成英文关键词 → 回车搜索。中间不用切翻译网页、不用复制粘贴，几乎无感。

再后来 `⌘⇧F` 划词翻译被加进来——日常看英文资料 / 文档时一键查中文意思，比开词典 / 复制到翻译网站快得多。

---

## 功能

- 🎯 **中文转英文**（`⌘⇧R`）：任何 app 的任何输入框都能用，结果自动整理成 kebab-case。文件命名、英文关键词搜索、变量名都行
- 🔍 **划词翻译**（`⌘⇧F`）：选中外文，弹出浮动面板显示中文译文，原文 / 译文都各自限高可滚动，长文自动折叠
- 🎭 **三种翻译风格**：**土翻 / 正翻 / 装翻**——日常用正翻；想搞点乐子时切土翻（`好好学习 → good good study`）；想装一下时切装翻（中文出文言文 / 古诗，英文混拉丁）
- 🛡 **风格化兜底**：土翻 / 装翻 偶尔抽风(模型乱续示例)时，自动用正翻翻译并在前面挂一行小蓝字「😅 太难了,我实在装不下去了…」，不会留你一个空响应
- ✂️ **kebab 翻译自动流程**：读取选中文字 → 调 AI 翻译 → 格式化为 kebab-case → 自动粘贴回去
- 🍱 **多家 AI 服务商**：OpenAI、智谱 GLM、DeepSeek、Kimi、MiniMax、通义千问、豆包，以及任意 OpenAI 兼容 endpoint
- 🎚 **每家独立配置**：API Key / endpoint / 模型分别按 provider 保存，切换后原值自动回填；endpoint 与模型都有「快捷选择」预设
- 🔐 **API Key 存 Keychain**，不落盘在任何明文配置里；输入框右侧可一键切换显示 / 隐藏
- 👻 **纯菜单栏常驻**，不占 Dock 格子，菜单栏图标是一条会心一笑的小鱼
- ⚡ **原生 Swift**，冷启动快，内存占用低，无第三方依赖

---

## 安装

### 直接下载（推荐普通用户）

从 [GitHub Releases](https://github.com/uxwangy-code/DumbTransPro/releases/latest) 下载最新的 `.zip`，解压后将 `DumbTransPro.app` 拖到「应用程序」文件夹即可。

macOS 13+ 可用。

### 从源码构建（推荐开发者）

```bash
git clone https://github.com/uxwangy-code/DumbTransPro.git
cd DumbTransPro

# 一次性：在本机生成自签代码签名证书
# （没有这一步会 fallback 到 adhoc，TCC 授权每次 rebuild 会失效）
bash scripts/setup-signing.sh

# 构建、签名并安装到「应用程序」
bash scripts/bundle.sh --install --launch
```

依赖：macOS 13+ · Xcode Command Line Tools（`xcode-select --install`）· OpenSSL（macOS 自带）。

> 📌 `setup-signing.sh` 会在 `~/Library/Keychains/dumbtrans-signing.keychain-db` 创建一张 10 年期的本地 self-signed 证书。这张证书**不会进 git**（私钥不能进仓库），所以**每台开发机都要跑一次**。换电脑或重装系统后再跑一次即可。

`--install` 默认会把应用安装到 `/Applications/瞎翻 Pro.app`，并刷新 Launch Services，让「应用程序」文件夹、Launchpad 和 Spotlight 能找到它。如果没有 `/Applications` 写入权限，可以改装到当前用户应用目录：

```bash
DUMBTRANS_INSTALL_DIR="$HOME/Applications" bash scripts/bundle.sh --install --launch
```

### 首次启动授权

第一次启动会在菜单栏小鱼图标下拉里看到 `⚠ 请授权辅助功能（点击打开设置）`：

1. 点击该菜单项，自动跳转到 **系统设置 → 隐私与安全性 → 辅助功能**
2. 启用 `DumbTransPro` 的开关
3. 回到 app，菜单里的警告会在 2 秒内自动消失

只需授权这一次。之后 rebuild 不用再操作（前提是用了 `setup-signing.sh` 的稳定签名）。

如果要取消授权：点击菜单栏小鱼图标 → `辅助功能权限：已授权（点击管理/取消）`，在系统设置里关闭 `瞎翻 Pro` / `DumbTransPro` 即可。

如果系统设置的辅助功能列表里看不到应用，先确认已安装到 `/Applications/瞎翻 Pro.app` 或 `~/Applications/瞎翻 Pro.app`。必要时可以重置旧授权记录后重新启动安装版：

```bash
tccutil reset Accessibility com.whimsycode.dumbtrans-pro
open "/Applications/瞎翻 Pro.app"
```

---

## 配置

点击菜单栏的小鱼图标 → **设置**，填入 API Key：

| 服务商 | 默认模型 | 申请地址 |
|--------|---------|---------|
| 智谱 GLM | `glm-4-flash`（免费额度够用） | https://open.bigmodel.cn |
| OpenAI | `gpt-4o-mini` | https://platform.openai.com |
| DeepSeek | `deepseek-v4-flash` | https://platform.deepseek.com |
| Kimi | `moonshot-v1-8k` | https://platform.moonshot.cn |
| MiniMax | `MiniMax-M2.7-highspeed` | https://platform.minimax.io |
| 通义千问 | `qwen-turbo` | https://bailian.console.aliyun.com |
| 豆包 | `doubao-lite-32k` | https://www.volcengine.com/product/ark |
| 自定义 | 任意 OpenAI 兼容 API | — |

> 推荐新手从 **智谱 GLM** 开始，注册即送额度，`glm-4-flash` 本身也是免费的。

设置面板的几个细节：

- **Endpoint** 与 **Model** 字段都可以手输入，也可点旁边的「快捷选择」用预设值（如智谱 Coding Plan 端点、Kimi 国内/国际、千问海外区域、DeepSeek beta 等）
- 每家 provider 的 API Key、endpoint、模型**独立保存**；切到别家再切回来时，原本填的值会自动回填
- 模型「快捷选择」只列**非推理模型**——推理模型对翻译质量收益小、却慢且贵；如要使用，手输入模型名即可
- 国内 provider 都有内容安全过滤，敏感话题会被服务端 400 拒绝并给出明确提示，可切到 OpenAI 重试

翻译风格可在设置中切换：

| 风格 | 提示文案 | 调性 |
|------|---------|------|
| 土翻 | 中式直译,差生专用,会英语的不要选 | 「好好学习 → good good study」「加油 → add oil」「人山人海 → people mountain people sea」逐字直译,中文骨架透过英文皮肤 |
| 正翻 | 默认推荐,追求自然准确,正常人首选 | 母语者风格,日常推荐 |
| 装翻 | 偶尔抽风会出文言文或者散文,没有文学修养不要轻易尝试 | 中→英 混拉丁与古英语(`项目→opus magnum`);英→中 按输入自选文言词 / 文言文段 / 五言七言诗 / 散文诗 |

> 翻译风格在「中文转英文」和「划词翻译」两个动作里都生效。土翻 / 装翻 模型抽风时会自动用正翻兜底,前面会出现一行小蓝字提示「😅 太难了,我实在装不下去了…」,不会让你看见模型乱续示例的翻车场面。

---

## 使用

### 中文转英文（`⌘⇧R`）

在 **任何** 输入框里都能用,常见场景:

- **文件命名**: Finder 选中文件名 → 输中文 → `⌘⇧R` → 自动替换成 `study-hard` 这种 kebab-case
- **英文关键词搜索**: Dribbble / Behance / Pinterest 这类英文设计平台搜素材时,搜索框里输中文 → `⌘⇧R` → 直接拿到英文关键词回车搜
- **变量 / 函数名**: IDE 里给变量起名,中文想好了不会翻 → 选中 → `⌘⇧R` → 出 kebab-case,稍微改改就能用
- **任意要英文的输入框**: 终端、浏览器地址栏、聊天框,只要能选中文字、能粘贴英文,都行

操作:选中中文 → 按 `⌘⇧R` → 等菜单栏小鱼变 ⏳ 再变回来(一般 500ms 内) → 选中的内容已被替换成 kebab-case 英文。

### 划词翻译（外文 → 中文）

在 **任何** app 里看英文资料/文档时：

1. 鼠标选中要查的句子或段落
2. 按 `⌘⇧F`
3. 屏幕中央弹出浮动面板，上方原文（>100 字自动折叠 + 展开按钮），下方按当前翻译风格显示中文译文，右下角显示当前用的模型名
4. 点面板右上角 × 关闭

---

## 开发

### 跨机器迁移开发

```bash
# 新机器
git clone https://github.com/uxwangy-code/DumbTransPro.git
cd DumbTransPro

# 必跑一次：生成本机自签证书
bash scripts/setup-signing.sh
```

之后正常开发即可。

### 常用命令

```bash
# 跑测试
swift test

# 开发期直接从终端跑（stderr log 直接看见）
swift run DumbTransPro

# 完整 build + sign + 打包 .app
bash scripts/bundle.sh

# 完整 build + sign + 安装到「应用程序」
bash scripts/bundle.sh --install

# 启动安装版
open "/Applications/瞎翻 Pro.app"
```

### Git workflow

```bash
git pull                              # 同步远端
# 改代码
swift test                            # 跑测试
git add -A && git commit -m "..."     # 提交
git push origin main                  # 推到 GitHub
```

仓库：https://github.com/uxwangy-code/DumbTransPro

### 项目结构

```
Sources/
├── DumbTransPro/main.swift           # NSApplication 入口
└── DumbTransProCore/                 # 核心逻辑（可测）
    ├── MenuBarManager.swift          # 菜单栏 + 辅助功能自检
    ├── HotkeyManager.swift           # Carbon RegisterEventHotKey
    ├── ClipboardManager.swift        # ⌘C/⌘V 模拟 + 选中文字捕获
    ├── TranslateService.swift        # OpenAI 兼容 API 调用
    ├── TranslationStyle.swift        # 翻译风格 + 快捷键动作
    ├── TextFormatter.swift           # kebab-case 格式化
    ├── SettingsStore.swift           # 配置持久化（Keychain + UserDefaults）
    ├── SettingsView.swift            # 设置面板 SwiftUI
    ├── KeychainHelper.swift          # API Key 安全存储
    ├── LookupPanelState.swift        # 划词翻译面板状态
    ├── LookupPanelView.swift         # 划词翻译面板 UI
    └── LookupPanelManager.swift      # 划词翻译面板窗口管理
Tests/                                # Swift Testing 单元测试(含 prompt 泄露检测 + 兜底链路)
Resources/                            # AppIcon.icns + MenuBarIcon*.png + Info.plist
scripts/
├── setup-signing.sh                  # 一次性创建本机自签代码签名证书
├── bundle.sh                         # build + sign + package
└── process-menubar-icon.py           # 把生成的剪影 PNG 转成 macOS template image
```

技术栈：Swift 6 · SwiftUI · Carbon RegisterEventHotKey · NSPasteboard + CGEvent · URLSession · Combine。无第三方 Swift 依赖，`Package.swift` 清清爽爽。

---

## 关于代码签名

`bundle.sh` 会**自动检测**是否有 `DumbTransPro Dev` 这张本地证书：

- **有** → 用它签名。Designated Requirement 基于证书指纹 + bundle id，**TCC 授权跨 rebuild 持久有效**
- **没有** → fallback 到 adhoc 签名，每次 rebuild 都要重新去系统设置里加一次辅助功能授权

`setup-signing.sh` 用 OpenSSL 生成一张 10 年期 self-signed code-signing 证书，存到独立 keychain（`~/Library/Keychains/dumbtrans-signing.keychain-db`），并通过 `set-key-partition-list` 预授权 codesign 访问，整个过程无 GUI 弹窗。

---

## Roadmap

- [x] GitHub Releases 提供签名好的 `.app` 下载，免去源码构建
- [x] 划词翻译（外文 → 中文）浮动面板
- [x] 稳定本地签名身份，TCC 授权一次永久
- [ ] 支持更多输出格式：`camelCase` / `PascalCase` / `snake_case`
- [ ] 可自定义快捷键
- [ ] 可自定义翻译 Prompt / 少样本示例
- [ ] 历史记录 + 一键复用

欢迎开 issue 提想法。

---

## License

[MIT](./LICENSE) © 2026 Thirty
