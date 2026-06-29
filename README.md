# 瞎翻 Pro · DumbTrans Pro

macOS 菜单栏翻译工具。选中文字，按快捷键，就在当前 app 里完成翻译，不用切浏览器，不用复制粘贴来回倒。

```text
未命名文件夹          ->  Cmd+Shift+R  ->  untitled-folder
登录按钮图层          ->  Cmd+Shift+R  ->  login-button-layer
最大重试次数          ->  Cmd+Shift+R  ->  max-retry-count
空状态插画            ->  Cmd+Shift+R  ->  empty-state-illustration
checkout flow        ->  Cmd+Shift+R  ->  结账流程
select text          ->  Cmd+Shift+F  ->  弹窗查看中文译文
```

## 功能

- **中英文原地互转**：`Cmd+Shift+R`，选中中文转英文，选中英文转中文，并直接替换原文。
- **短词自动格式化**：适合文件名、搜索词、变量名，短词会整理成 `kebab-case`。
- **划词翻译**：`Cmd+Shift+F`，选中外文后弹出中文译文，不改动原文。
- **三种风格**：土翻、正翻、装翻。日常用正翻，另外两个用于娱乐化或风格化表达。
- **离线翻译**：macOS 15+ 可用 Apple 设备端翻译，免 API key，不联网。
- **多家 AI 服务商**：支持 OpenAI、智谱 GLM、DeepSeek、Kimi、MiniMax、通义千问、豆包和自定义 OpenAI 兼容 endpoint。
- **本地安全存储**：API key 和 License key 存在 macOS Keychain，不写入明文配置。

## 翻译风格

风格可以在设置里切换，在中英文原地互转和划词翻译里都会生效：

| 风格 | 适合 | 输出倾向 |
|---|---|---|
| 土翻 | 想要一点中式直译的梗味 | `好好学习 -> good-good-study`、`加油 -> add-oil`，故意保留中文骨架 |
| 正翻 | 默认日常翻译 | 自然、准确，适合工作命名、资料阅读和中英文互转 |
| 装翻 | 偶尔想要文艺或古典味 | 中译英会更书面，英译中可能变成文言、散文或诗化表达 |

土翻和装翻需要 AI；离线翻译只提供正翻。遇到异常输出时，应用会自动兜底，避免把解释、示例或模型回复粘回原处。

## 系统要求

- Apple Silicon Mac
- macOS 13+
- macOS 15+ 才支持离线翻译
- macOS 13 / 14 需要配置 AI key 才能翻译

## 安装

从 [GitHub Releases](https://github.com/uxwangy-code/DumbTransPro/releases/latest) 下载最新 `.zip`，解压后把 `DumbTransPro.app` 拖到「应用程序」。

首次启动后，按菜单栏小鱼图标里的提示开启：

```text
系统设置 -> 隐私与安全性 -> 辅助功能 -> 启用 DumbTransPro
```

没有辅助功能权限时，快捷键无法读取选中文字，也无法自动粘贴回去。

## 配置

macOS 15+ 可以先不填 API key，直接用离线翻译测试正翻和划词翻译。

如果要使用 AI 翻译、土翻、装翻或 macOS 13 / 14，请打开菜单栏小鱼图标 -> 设置，选择服务商并填写 API key。

免费版：

- macOS 15+ 离线翻译不限次
- AI 翻译支持 OpenAI、智谱 GLM
- 每日 30 次 AI 翻译

Pro：

- 解锁全部服务商
- AI 翻译不限次数
- 一次买断

## 常用快捷键

| 功能 | 默认快捷键 | 行为 |
|---|---|---|
| 中英文原地互转 | `Cmd+Shift+R` | 替换选中文字 |
| 划词翻译 | `Cmd+Shift+F` | 弹窗显示译文 |

快捷键可以在设置面板里重新录制。

## 从源码构建

```bash
git clone https://github.com/uxwangy-code/DumbTransPro.git
cd DumbTransPro

# 每台开发机跑一次：创建本地签名证书，让辅助功能权限跨 rebuild 保持稳定
bash scripts/setup-signing.sh

# 构建、签名、安装并启动
bash scripts/bundle.sh --install --launch
```

常用开发命令：

```bash
swift test
swift run DumbTransPro
bash scripts/bundle.sh
bash scripts/bundle.sh --install --launch
```

匿名使用数据本地验证：

```bash
bash scripts/verify-telemetry-local.sh
cat build/telemetry/events.jsonl
```

正式查看用户更新后的匿名使用数据，需要先部署 HTTPS 收集端，再在打包/发版时设置。切到自建授权服务时，同时注入购买入口和 license 校验接口；未配置校验接口时会继续使用 Gumroad 旧 key 校验：

```bash
DUMBTRANS_USAGE_TELEMETRY_URL="https://your-domain.example/events" \
DUMBTRANS_LICENSE_PURCHASE_URL="https://uxwangy-code.github.io/DumbTransPro/#pricing" \
DUMBTRANS_LICENSE_VERIFY_URL="https://license.whimsycode.com/api/licenses/verify" \
  bash scripts/bundle.sh
```

GitHub Pages 只能托管静态文件，不能接收 App 发来的 `POST /events`。

## 项目结构

```text
Sources/DumbTransPro/                 # app 入口
Sources/DumbTransProCore/             # 菜单栏、快捷键、翻译、设置、License
Tests/DumbTransProCoreTests/          # Swift Testing 单元测试
Resources/                            # Info.plist、图标资源
docs/                                 # GitHub Pages、隐私/条款页面
scripts/                              # 构建与签名脚本
```

## License

[Source-Available](./LICENSE) © 2026 WhimsyCode (Thirty)

代码公开，欢迎阅读、学习、提 PR；个人可自行编译在自己的设备上使用。不允许分发二进制或商用。v1.2.3 及更早版本仍为 MIT。
