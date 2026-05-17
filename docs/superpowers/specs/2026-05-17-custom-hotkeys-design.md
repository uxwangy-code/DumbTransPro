# 自定义全局快捷键 — 设计文档

**日期**：2026-05-17
**作者**：Thirty + Claude
**状态**：待实现

## 背景

DumbTransPro 当前两个翻译动作的全局快捷键写死在代码里：

- `中文转英文`：`⌘⇧R`（`TranslationStyle.swift:181`）
- `划词翻译`：`⌘⇧F`（同上）

modifier 在 `HotkeyManager.swift:38` 硬编码为 `cmdKey | shiftKey`。用户无法修改，遇到与其他 app 冲突时只能干瞪眼。

## 目标

让用户在设置面板里自定义这两个动作的快捷键，参考 macOS 系统设置 / 主流菜单栏 app 的"芯片式录制器"交互。具体行为：

- 显示当前组合（如 `⌘⇧R`），右侧 `⊗` 清空
- 点击芯片进入录制态，按下合法组合**自动保存生效**（不走 Save 按钮）
- 录制中右侧 `↺` 可重置为默认值，`Esc` 取消，`Delete/Backspace` 清空，`Tab` 移焦
- 清空后菜单栏对应行变成可点击触发（保证功能不丢）
- 与系统 / 主菜单冲突 → 黄色软警告（仍允许保存）
- 与另一动作内部冲突 → 红色阻断（不保存）

## 非目标

- 拖拽排序、profile 切换、导入/导出 hotkey 配置 → YAGNI
- 支持纯 modifier 触发（如"右 Ctrl"单按）→ 不在第一版
- 给菜单栏 dropdown 内嵌录制器 → 不做，菜单栏只读展示
- 增加其他可配置 action（如"用某模型翻译"）→ 不在本次范围

## 调研结论摘要

调研了 macOS 翻译/工具类 app 的全局快捷键实现：

| 工具 | 注册底层 | Recorder UI | 备注 |
|---|---|---|---|
| Easydict | Magnet | KeyHolder | 3 个第三方依赖 |
| Plash / Dato 等 | KeyboardShortcuts | KeyboardShortcuts.Recorder | sindresorhus 出品 |
| 大量小型菜单栏 app | KeyboardShortcuts | 同上 | macOS 生态事实标准 |

**结论**：macOS Swift 原生 app 主流是引入第三方依赖，KeyboardShortcuts 是事实标准（5 年迭代 / MIT 协议）。深读其源码后，发现几个我们原本会踩坑的关键设计：

1. 用 macOS 系统 API `CopySymbolicHotKeys` **动态查询**系统已注册快捷键，比硬编码黑名单准确得多
2. 录制中必须**暂停所有已注册热键**，否则用户按旧组合测试时会真触发动作
3. modifier 校验：纯 ⇧ 不算（Carbon 不递送），必须 ≥1 of `{⌘, ⌃, ⌥}`
4. 主菜单 `keyEquivalent` 递归遍历检测冲突
5. 设置窗 `windowDidResignKey` 退出录制；进窗口时 `preventBecomingKey()` 阻止芯片自动获焦

## 实现策略：Vendor + 自写 UI（方案 C）

不引入 SPM 依赖，**vendor** KeyboardShortcuts 的关键底层文件（5 个），保留 MIT 署名；UI 层（芯片录制器）按截图自写 SwiftUI。

理由：

- 项目至今零外部依赖，保持调性
- 底层 Carbon 注册 / 系统快捷键查询是踩了无数次坑后才稳定的代码，自己重写是浪费
- 但 KeyboardShortcuts.Recorder 是 `NSSearchField` 风格，与截图里的 SwiftUI 芯片差距较大，自己写更划算
- 一次性 vendor 之后基本不需要更新（Carbon API 多年未动）

## 架构

### 文件清单

#### 新增：Vendored from KeyboardShortcuts

放 `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/`，文件头标注 MIT 署名：

| 文件 | 上游来源 | 职责 |
|---|---|---|
| `KS_HotKey.swift` | `HotKey.swift` 前段 | 单个全局热键封装，析构时自动反注册 |
| `KS_HotKeyCenter.swift` | `HotKey.swift` 末段 | 单例：Carbon EventHandler 装载、register/unregister/pause/resume |
| `KS_SystemShortcuts.swift` | `Utilities.swift` 中 `CopySymbolicHotKeys` 部分 | 查询系统已注册快捷键 |
| `KS_MainMenu.swift` | `Shortcut.swift` 中 `menuItemWithMatchingShortcut` | 递归遍历 `NSApp.mainMenu` 找冲突 |
| `KS_ModifierFlags+Carbon.swift` | `Utilities.swift` 部分 | `NSEvent.ModifierFlags` ↔ Carbon UInt32 互转 / 规范化 |
| `KS_LocalEventMonitor.swift` | `Utilities.swift` 部分 | 录制时的 NSEvent monitor 简单包装 |

`KS_HotKeyCenter` 内部使用 signature `0x44545052`（"DTPR"），与现有 `HotkeyManager.swift:39` 保持一致，避免与 KS 上游 signature `0x53534B53`（"SSKS"）冲突。

#### 新增：我们自己写的

| 文件 | 职责 |
|---|---|
| `HotkeyConfig.swift` | 项目 config 类型 + display formatter + 默认值定义（modifier 合法性校验在录制器里做，不下沉到 config 类型） |
| `HotkeyChipView.swift` | SwiftUI 芯片录制器，纯 dumb component |
| `HotkeySection.swift` | 设置面板"快捷键"分区，做冲突校验、连 store、控制软警告横幅 |

#### 改动

| 文件 | 改动要点 |
|---|---|
| `TranslationStyle.swift` | 删 `TranslationAction.keyCode` / `hotkeyLabel`；加 `defaultHotkey: HotkeyConfig`；保留 `hotkeyID` |
| `SettingsStore.swift` | 加 `@Published hotkeys: [TranslationAction: HotkeyConfig?]`；加 `hotkey(for:)` / `setHotkey(_:for:)` / `resetHotkey(for:)`；UserDefaults JSON 持久化 |
| `HotkeyManager.swift` | 重写：内部调用 `KS_HotKeyCenter`，对外保留 `start(initial:)` / `stop()` / `reregister(action:hotkey:)`；新增 `pauseAll()` / `resumeAll()` |
| `SettingsView.swift` | 在 `translationStyleSection` 之上插入 `HotkeySection(store: store)` |
| `MenuBarManager.swift` | `populateMenu` 双形态（有 hotkey = 灰色标签 / 无 hotkey = 可点击触发）；订阅 `store.$hotkeys` 自动重建菜单 |

## 数据模型

### `HotkeyConfig`

```swift
public struct HotkeyConfig: Codable, Equatable, Sendable, Hashable {
    public let keyCode: UInt32       // Carbon kVK_*
    public let modifiers: UInt32     // cmdKey | shiftKey | optionKey | controlKey 的位或

    public var displayString: String { /* "⌘⇧R" / "⌃F1" / "⌘⌥Space" */ }
}
```

`nil` 表示用户**显式清空**。

### `TranslationAction.defaultHotkey`

```swift
public var defaultHotkey: HotkeyConfig {
    switch self {
    case .rewriteToEnglish: return HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
    case .lookup:           return HotkeyConfig(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey))
    }
}
```

### 持久化

每个 action 一个 UserDefaults key：

```
hotkey.rewriteToEnglish  → JSON {keyCode, modifiers} | "null"
hotkey.lookup            → JSON {keyCode, modifiers} | "null"
```

读取语义：

- key 不存在 → 用 `defaultHotkey`（首次启动 / 老用户升级）
- key 存在值 `null` → 用户**显式清空**，使用 nil
- key 存在值 JSON → 用户自定义值

老用户兼容：不需要写迁移代码，键不存在自动落到默认。

### Display Formatter

放 `HotkeyConfig.displayString`，使用查表法，覆盖以下范围：

- A–Z / 0–9 → 大写字母 / 数字字符
- F1–F19 → `F1`..`F19`
- Space / Tab / Return / Escape / Delete / 方向键 / Home / End / PageUp / PageDown → 人类可读符号
- Modifier 拼接顺序固定 `⌃⌥⇧⌘`（macOS 习惯）

实现细节：keyCode 表内含约 60 个条目，未识别 keyCode 显示为 `?{code}`（防御性）。

## HotkeyManager 接口

```swift
@MainActor
public final class HotkeyManager {
    public var onAction: (@MainActor (TranslationAction) -> Void)?

    /// 装 Carbon EventHandler 一次，然后按 initial 注册
    public func start(initial: [TranslationAction: HotkeyConfig?]) -> [TranslationAction: RegisterError?]

    /// 反注册所有 + 卸载 EventHandler
    public func stop()

    /// 运行时换绑。nil = 仅反注册
    public func reregister(action: TranslationAction, hotkey: HotkeyConfig?) -> RegisterError?

    /// 录制时调用：临时反注册所有热键
    public func pauseAll()

    /// 录制结束时调用
    public func resumeAll()

    public enum RegisterError: Error, Equatable {
        case duplicateInProcess   // eventHotKeyExistsErr
        case invalidParameter     // paramErr
        case unknown(OSStatus)
    }
}
```

内部用字典 `[TranslationAction: KS_HotKey]` 持有 vendored 类型。Vendor 时把 `KS_HotKey` 从上游的 `init?` 改成 `init(...) throws` 并暴露 `OSStatus`，这样上层能区分 `eventHotKeyExistsErr` / `paramErr` / 其他，分别映射到 `RegisterError` 三个 case。

## SettingsStore 改动

```swift
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var hotkeys: [TranslationAction: HotkeyConfig?] = [:]
    @Published public private(set) var registrationErrors: [TranslationAction: HotkeyManager.RegisterError] = [:]

    public func hotkey(for action: TranslationAction) -> HotkeyConfig?
    public func setHotkey(_ config: HotkeyConfig?, for action: TranslationAction)
    public func resetHotkey(for action: TranslationAction)  // 回 defaultHotkey
    public func setRegistrationError(_ error: HotkeyManager.RegisterError?, for action: TranslationAction)
}
```

`setHotkey` 内部：

1. 写入 `hotkeys[action]`
2. 持久化到 UserDefaults
3. **不直接调 HotkeyManager**——由 `MenuBarManager` 通过 Combine 订阅 `$hotkeys` 触发

这样 store 保持纯数据层、不依赖 manager 实现。

## 数据流

```
用户在 HotkeyChipView 按下合法组合
   ↓
HotkeySection 收到 onChange(config)
   ↓
HotkeySection 做应用内冲突 / 系统冲突 / 主菜单冲突 三类校验
   ├─ 应用内冲突 → 不调 store，RecorderView 切换 .conflict 红色态
   ├─ 系统冲突 / 主菜单冲突 → 仍 setHotkey + 黄色软警告横幅
   └─ 无冲突 → setHotkey + 清除警告
   ↓
SettingsStore.setHotkey
   ├─ 写 @Published hotkeys
   └─ 写 UserDefaults
   ↓
MenuBarManager 订阅 $hotkeys.sink 收到变化
   ├─ 调 hotkeyManager.reregister(action, config)
   ├─ 记录注册错误（若有）→ store.setRegistrationError
   └─ updateMenu() 重建 NSMenu（有 hotkey = 标签 / 无 = 可点击）
```

## UI 状态机

### `HotkeyChipView` 状态机（5 个状态）

```swift
indirect enum RecorderState: Equatable {
    case resting                                // 显示组合 + ⊗
    case recording(returnTo: RecorderState)     // 蓝边框、占位"按下快捷键…"、右侧 ↺
    case cleared                                // "点击设置" 按钮态
    case conflict(label: String, returnTo: RecorderState)  // 录制态变红 + 下方红色小字
    case warning(label: String)                 // resting 变种 + 下方黄色软警告小字（系统/主菜单冲突）
}
```

`recording` 和 `conflict` 都带 `returnTo`，存"按 Esc / 失焦时该回到哪个状态"，避免在 View 层维护额外的 previousState 字段。

### 状态转移

```
resting/warning --[点击芯片]--> recording
resting/warning --[点击 ⊗]--> cleared

cleared --[点击"点击设置"]--> recording

recording(returnTo: X) --[Esc]--> X
recording(returnTo: X) --[Delete/Backspace]--> cleared
recording(returnTo: X) --[Tab]--> X (并把焦点移到下一个控件，事件冒泡)
recording(returnTo: X) --[点击 ↺]--> resting (回默认值，触发 commit(defaultHotkey))
recording(returnTo: X) --[失焦 / 点击芯片外]--> X
recording(returnTo: X) --[按下合法组合 + 应用内冲突]--> conflict(label, returnTo: X)
recording(returnTo: X) --[按下合法组合 + 系统冲突]--> warning(label) (保存 + 软警告)
recording(returnTo: X) --[按下合法组合 + 主菜单冲突]--> warning(label) (保存 + 软警告)
recording(returnTo: X) --[按下合法组合 + 无冲突]--> resting (保存)
recording(returnTo: X) --[按下非法组合(无 ⌘⌃⌥)]--> 保持 recording + NSSound.beep()

conflict(label, returnTo: X) --[按新合法组合]--> recording → 走相同分流
conflict(label, returnTo: X) --[Esc / 失焦]--> X
```

### 状态机抽 Reducer

把状态转换抽出纯函数：

```swift
func reduce(state: RecorderState, event: RecorderEvent) -> (newState: RecorderState, effects: [Effect])

enum RecorderEvent {
    case chipClicked
    case clearClicked
    case escPressed
    case deleteOrBackspacePressed
    case tabPressed
    case resetClicked
    case focusLost
    case keyDown(config: HotkeyConfig, conflict: ConflictKind)
    case invalidKeyDown
}

enum Effect {
    case installMonitor
    case removeMonitor
    case pauseAllHotkeys
    case resumeAllHotkeys
    case commit(HotkeyConfig?)
    case resetToDefault
    case beep
    case moveFocusToNextResponder
}

enum ConflictKind {
    case appInternal(otherActionTitle: String)
    case system
    case mainMenu(itemTitle: String)
    case none
}
```

View 层根据 Effects 做副作用，状态机本身可纯函数单测。`HotkeyChipView` 不直接依赖 `HotkeyManager`——`pauseAllHotkeys` / `resumeAllHotkeys` 这类 effect 通过回调（`onRecordingStarted` / `onRecordingEnded`）由 `HotkeySection` 转给 manager 执行。

## 录制态键盘捕获

进入 `recording` 状态时 effects 包含 `installMonitor` + `pauseAllHotkeys`：

```swift
func installMonitor() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            dispatch(.escPressed)
            return nil
        }
        if event.type == .keyDown,
           (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
            dispatch(.deleteOrBackspacePressed)
            return nil
        }
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Tab) {
            dispatch(.tabPressed)
            return event  // 冒泡让焦点移走
        }
        if event.type == .flagsChanged {
            previewModifiers = event.modifierFlags
            return nil
        }
        // keyDown 合法组合判定
        let mods = event.modifierFlags.subtracting([.shift, .function])
        guard !mods.isEmpty else {
            dispatch(.invalidKeyDown)
            return nil
        }
        let config = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags.carbonRepresentation)
        let conflict = detectConflict(config)  // HotkeySection 注入
        dispatch(.keyDown(config: config, conflict: conflict))
        return nil
    }
}
```

## 冲突检测

`HotkeySection.detectConflict(config, for: action) -> ConflictKind`（无冲突返回 `.none`）：

```swift
func detectConflict(_ config: HotkeyConfig, for action: TranslationAction) -> ConflictKind {
    // 1. 应用内: 另一个 action 已占用
    if let other = TranslationAction.allCases.first(where: {
        $0 != action && store.hotkey(for: $0) == config
    }) {
        return .appInternal(otherActionTitle: other.title)
    }

    // 2. 主菜单: 当前 NSApp.mainMenu 里 keyEquivalent 匹配
    if let item = config.takenByMainMenu {
        return .mainMenu(itemTitle: item.title)
    }

    // 3. 系统: CopySymbolicHotKeys 列表
    if config.isTakenBySystem {
        return .system
    }

    return .none
}
```

应用内冲突走红色阻断；后两类走黄色软警告但仍保存。

## 菜单栏 Fallback

`MenuBarManager.populateMenu` 改动：

```swift
for action in TranslationAction.allCases {
    let item: NSMenuItem
    if let cfg = settingsStore.hotkey(for: action) {
        item = NSMenuItem(title: "\(action.title)  \(cfg.displayString)", action: nil, keyEquivalent: "")
        item.isEnabled = false
    } else {
        item = NSMenuItem(title: action.title, action: #selector(menuActionTriggered(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
    }
    menu.addItem(item)
}

@objc private func menuActionTriggered(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? TranslationAction else { return }
    handleAction(action)
}
```

订阅触发刷新：

```swift
settingsStore.$hotkeys
    .sink { [weak self] _ in self?.updateMenu() }
    .store(in: &cancellables)
```

## 设置窗 Focus 管理

借鉴 KeyboardShortcuts 的两个机制：

### 1. 防止初次自动获焦

`HotkeyChipView` 在 `onAppear` 时：

```swift
.onAppear {
    DispatchQueue.main.async {
        // 让 SettingsView 的初始 first responder 不是芯片
        if let window = NSApp.keyWindow, window.firstResponder === self.underlyingView {
            window.makeFirstResponder(nil)
        }
    }
}
```

### 2. 窗口失焦自动退出录制态

```swift
.onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
    if isRecording {
        dispatch(.focusLost)
    }
}
```

## 边界情况

| 情况 | 处理 |
|---|---|
| 首次启动 / 老用户升级 | UserDefaults 键缺失 → 落到 `defaultHotkey`，行为不变 |
| 用户清空 → 退出 app → 重启 | UserDefaults 存 `null`，读出后仍为 nil（不回默认） |
| 用户两个 action 设成同一组合（绕过 UI 校验，例如手改 UserDefaults） | HotkeyManager.reregister 第二次返回 `.duplicateInProcess`，store.registrationErrors 记录，HotkeySection 显红色横幅 |
| 录制中按 Cmd+Q | NSEvent monitor 拦截、return nil → 不会触发系统退出。仍按合法组合检测路径（命中"主菜单冲突"软警告） |
| 录制时设置窗被遮挡（NSWindow 失 key 但未关） | `windowDidResignKey` 通知 → 自动退出录制态，回到 previousState |
| 系统快捷键列表运行时变化（用户在 macOS 设置里加了一个） | 下次进入录制时重新查询 `CopySymbolicHotKeys`，自然刷新 |

## 测试策略

### `HotkeyConfigTests`

- `displayString_letters_matches`：A-Z 全覆盖
- `displayString_modifierOrder`：随机输入 modifier 集合，验证输出始终 `⌃⌥⇧⌘` 顺序
- `displayString_functionKeys`：F1-F19
- `displayString_specialKeys`：Space / Tab / Return / Esc / 方向 / Delete
- `displayString_unknownKeyCode`：返回 `?{code}` fallback
- `codable_roundTrip`：JSON 序列化往返

### `RecorderReducerTests`（针对 reduce 纯函数）

- `chipClicked_fromResting_transitionsToRecordingWithReturnToResting_andEmitsInstallMonitorAndPause`
- `chipClicked_fromCleared_transitionsToRecordingWithReturnToCleared`
- `esc_inRecording_returnsToReturnToState_andEmitsRemoveMonitorAndResume`
- `delete_inRecording_transitionsToCleared`
- `tab_inRecording_returnsToReturnToStateAndMovesFocus`
- `validKeyDown_noConflict_emitsCommit_andReturnsToResting`
- `validKeyDown_appInternalConflict_transitionsToConflict_noCommit`
- `validKeyDown_systemConflict_transitionsToWarning_andCommits`
- `validKeyDown_mainMenuConflict_transitionsToWarning_andCommits`
- `invalidKeyDown_keepsRecording_emitsBeep`
- `resetClicked_inRecording_emitsCommitDefault_andReturnsToResting`
- `clearClicked_inResting_transitionsToCleared_emitsCommitNil`
- `focusLost_inRecording_returnsToReturnToState`
- `escFromConflict_returnsToConflictReturnToState`

### `HotkeyManagerTests`

- `start_withNilConfigs_registersNothing`
- `start_returnsErrorsPerAction`
- `reregister_clearsAndReplaces`
- `reregister_withNil_unregisters`
- `reregister_sameComboTwice_returnsDuplicateError`
- `pauseAll_unregistersAll_resumeAll_reregisters`

### `SettingsStoreTests`（hotkey 部分）

- `hotkey_unsetKey_returnsDefault`
- `hotkey_explicitNil_returnsNil`
- `setHotkey_persistsToUserDefaults`
- `resetHotkey_restoresDefault`

### 不测的

- 真实 Carbon 注册触发系统事件（依赖 OS）
- `NSEvent.addLocalMonitorForEvents` 在测试环境的行为
- KS vendored 文件内部逻辑（上游已测）

## 部署/迁移

无需迁移脚本。老用户首次升级后：

- UserDefaults 中无 `hotkey.*` 键 → 自动落到 `defaultHotkey`
- 行为完全不变，仅多出"快捷键"设置分区

## 范围外（后续可能）

- 让翻译风格选择也支持热键直选（如 ⌘⇧1/2/3 切土翻 / 正翻 / 装翻）
- 录制纯 modifier 触发（如双击右 Ctrl）
- 配置导入 / 导出 JSON
- macOS 系统设置面板 deep link（"已被 Mission Control 占用" 旁边给一个按钮跳转）

## 引用

- KeyboardShortcuts by Sindre Sorhus — https://github.com/sindresorhus/KeyboardShortcuts (MIT)
- macOS `CopySymbolicHotKeys` — HIToolbox / Carbon framework
- Easydict 的 KeyHolderWrapper 实现 — https://github.com/tisfeng/Easydict/blob/main/Easydict/Swift/Feature/Shortcut/View/KeyHolderWrapper.swift
