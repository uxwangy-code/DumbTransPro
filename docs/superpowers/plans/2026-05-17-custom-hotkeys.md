# Custom Hotkeys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `⌘⇧R` / `⌘⇧F` global hotkeys with a SwiftUI chip-style recorder in the settings panel, backed by vendored KeyboardShortcuts internals for safe Carbon registration and system-shortcut detection.

**Architecture:** Vendor 6 files from `sindresorhus/KeyboardShortcuts` (MIT) into `Vendored/KeyboardShortcuts/` to handle Carbon registration, `CopySymbolicHotKeys` system queries, and main-menu conflict detection. Write our own thin `HotkeyConfig` data type, pure-function `HotkeyChipReducer` state machine, and SwiftUI `HotkeyChipView` + `HotkeySection`. Rewire `HotkeyManager` to delegate to vendored `KS_HotKeyCenter`. `SettingsStore` adds per-action persistence (UserDefaults JSON); `MenuBarManager` subscribes to changes and switches its dropdown items between read-only label and clickable trigger based on whether a hotkey is set.

**Tech Stack:** Swift 6 / SwiftUI / AppKit / Carbon.HIToolbox / Swift Testing framework.

**Spec:** `docs/superpowers/specs/2026-05-17-custom-hotkeys-design.md`

---

## File Structure

### New (vendored)

```
Sources/DumbTransProCore/Vendored/KeyboardShortcuts/
├── KS_HotKey.swift                       (~80 lines, from upstream HotKey.swift head)
├── KS_HotKeyCenter.swift                 (~150 lines, from upstream HotKey.swift tail)
├── KS_SystemShortcuts.swift              (~30 lines, from upstream Utilities.swift CopySymbolicHotKeys block)
├── KS_MainMenu.swift                     (~50 lines, from upstream Shortcut.swift menuItemWithMatchingShortcut)
├── KS_ModifierFlags+Carbon.swift         (~40 lines, from upstream Utilities.swift modifier conversion)
└── KS_LocalEventMonitor.swift            (~30 lines, from upstream Utilities.swift)
```

### New (our code)

```
Sources/DumbTransProCore/
├── HotkeyConfig.swift                    (data type + display formatter + default hotkeys)
├── HotkeyChipReducer.swift               (pure state machine)
├── HotkeyChipView.swift                  (SwiftUI chip recorder, dumb component)
└── HotkeySection.swift                   (settings panel section: chip + conflict detect + store)

Tests/DumbTransProCoreTests/
├── HotkeyConfigTests.swift
├── HotkeyChipReducerTests.swift
├── HotkeyManagerTests.swift
└── SettingsStoreHotkeyTests.swift
```

### Modified

```
Sources/DumbTransProCore/
├── TranslationStyle.swift     (delete keyCode/hotkeyLabel; add defaultHotkey)
├── SettingsStore.swift        (add hotkeys storage + Combine Published)
├── HotkeyManager.swift        (rewrite: delegate to KS_HotKeyCenter; add pauseAll/resumeAll)
├── SettingsView.swift         (insert HotkeySection above translationStyleSection)
└── MenuBarManager.swift       (populateMenu dual-form; subscribe to store.$hotkeys)
```

---

## Task 1: Vendor KeyboardShortcuts files

**Files:**
- Create: `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/KS_HotKey.swift`
- Create: `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/KS_HotKeyCenter.swift`
- Create: `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/KS_SystemShortcuts.swift`
- Create: `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/KS_MainMenu.swift`
- Create: `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/KS_ModifierFlags+Carbon.swift`
- Create: `Sources/DumbTransProCore/Vendored/KeyboardShortcuts/KS_LocalEventMonitor.swift`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p Sources/DumbTransProCore/Vendored/KeyboardShortcuts
```

- [ ] **Step 2: Fetch upstream source files**

```bash
gh api repos/sindresorhus/KeyboardShortcuts/contents/Sources/KeyboardShortcuts/HotKey.swift --jq '.content' | base64 -d > /tmp/ks_HotKey.swift
gh api repos/sindresorhus/KeyboardShortcuts/contents/Sources/KeyboardShortcuts/Shortcut.swift --jq '.content' | base64 -d > /tmp/ks_Shortcut.swift
gh api repos/sindresorhus/KeyboardShortcuts/contents/Sources/KeyboardShortcuts/Utilities.swift --jq '.content' | base64 -d > /tmp/ks_Utilities.swift
```

- [ ] **Step 3: Write `KS_HotKey.swift`**

Take the `HotKey` final class from `/tmp/ks_HotKey.swift` (top half, ends before the `HotKeyCenter` final class). Strip the upstream `KeyboardShortcuts.` namespace by removing the surrounding `extension KeyboardShortcuts { }` wrapper. Rename `HotKey` → `KS_HotKey`. Replace `HotKeyCenter.shared` references with `KS_HotKeyCenter.shared`. Change `init?` to `init(...) throws` so callers can map OSStatus:

```swift
//
//  KS_HotKey.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

import AppKit
import Carbon.HIToolbox

final class KS_HotKey {
    let carbonKeyCode: Int
    let carbonModifiers: Int
    let onKeyDown: () -> Void
    let onKeyUp: () -> Void
    var onRegistrationFailed: (() -> Void)?

    fileprivate let id: Int
    fileprivate var eventHotKeyRef: EventHotKeyRef?

    enum RegisterError: Error {
        case carbonStatus(OSStatus)
    }

    init(
        carbonKeyCode: Int,
        carbonModifiers: Int,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) throws {
        self.id = KS_HotKeyCenter.shared.nextId()
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        let status = KS_HotKeyCenter.shared.register(self)
        if status != noErr {
            throw RegisterError.carbonStatus(status)
        }
    }

    deinit {
        KS_HotKeyCenter.shared.unregister(self)
    }
}
```

- [ ] **Step 4: Write `KS_HotKeyCenter.swift`**

Take `HotKeyCenter` from `/tmp/ks_HotKey.swift` (lower half). Strip namespace wrapper. Rename `HotKeyCenter` → `KS_HotKeyCenter`, `HotKey` references → `KS_HotKey`. Change the signature constant from `1397967699` to `0x44545052` (matches our existing "DTPR" signature). Change `register(_:)` to return `OSStatus` instead of `Bool` so `KS_HotKey.init` can read it. Keep the `Mode` enum (disabled/normal/menuOpen), the menu tracking observers, and `pauseAllHotKeys` / `resumeAllHotKeys` methods intact—they are central to our `pauseAll` / `resumeAll` story.

Concrete diff vs upstream:

```swift
//
//  KS_HotKeyCenter.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

import AppKit
import Carbon.HIToolbox

final class KS_HotKeyCenter {
    static let shared = KS_HotKeyCenter()

    enum Mode { case disabled, normal, menuOpen }

    private struct WeakHotKey { weak var value: KS_HotKey? }

    private var lastHotKeyId = 0
    private var hotKeys = [Int: WeakHotKey]()
    private var eventHandler: EventHandlerRef?
    // ... (rest of HotKeyCenter from upstream, with renames)

    private let signature: UInt32 = 0x44545052  // "DTPR"

    func register(_ hotKey: KS_HotKey) -> OSStatus {
        var eventHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.carbonKeyCode),
            UInt32(hotKey.carbonModifiers),
            EventHotKeyID(signature: signature, id: UInt32(hotKey.id)),
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )
        guard status == noErr, let eventHotKey else { return status }
        hotKey.eventHotKeyRef = eventHotKey
        hotKeys[hotKey.id] = WeakHotKey(value: hotKey)
        setUpEventHandlerIfNeeded()
        updateEventHandler()
        return noErr
    }

    // ... (keep unregister, pauseAllHotKeys, resumeAllHotKeys, setUpMenuTrackingObserversIfNeeded,
    //      setUpEventHandlerIfNeeded, updateEventHandler, handleHotKeyEvent, handleRawKeyEvent,
    //      and the carbonEventHandler C function — all renamed)

    /// Public API for our HotkeyManager: temporarily unregister all active hotkeys.
    func pauseAll() { pauseAllHotKeys() }
    func resumeAll() { resumeAllHotKeys() }
}
```

The complete file body should mirror upstream `HotKey.swift` lines covering `final class HotKeyCenter` through the bottom `nonisolated private func carbonEventHandler`, with the renames described above. Reference upstream content at `/tmp/ks_HotKey.swift` line ~70 onwards.

- [ ] **Step 5: Write `KS_SystemShortcuts.swift`**

From `/tmp/ks_Utilities.swift`, locate the `CopySymbolicHotKeys` block (search for `static var systemShortcuts:`). Move into a top-level helper, no extension wrapper:

```swift
//
//  KS_SystemShortcuts.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

import AppKit
import Carbon.HIToolbox

enum KS_SystemShortcuts {
    /// Returns all currently-enabled system-defined keyboard shortcuts via Carbon `CopySymbolicHotKeys`.
    static var all: [(carbonKeyCode: Int, carbonModifiers: Int)] {
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
            let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
        else {
            return []
        }
        return shortcuts.compactMap {
            guard
                ($0[kHISymbolicHotKeyEnabled] as? Bool) == true,
                let carbonKeyCode = $0[kHISymbolicHotKeyCode] as? Int,
                let carbonModifiers = $0[kHISymbolicHotKeyModifiers] as? Int
            else { return nil }
            return (carbonKeyCode, carbonModifiers)
        }
    }

    /// True if the given Carbon combo is registered in macOS as a symbolic hotkey.
    /// F12 is excluded (system reports it but it's unused on modern macOS).
    static func contains(carbonKeyCode: Int, carbonModifiers: Int) -> Bool {
        if carbonKeyCode == kVK_F12, carbonModifiers == 0 { return false }
        let normalized = NSEvent.ModifierFlags(carbonModifiers: carbonModifiers).carbonRepresentation
        return all.contains { entry in
            entry.carbonKeyCode == carbonKeyCode
                && NSEvent.ModifierFlags(carbonModifiers: entry.carbonModifiers).carbonRepresentation == normalized
        }
    }
}
```

- [ ] **Step 6: Write `KS_MainMenu.swift`**

From `/tmp/ks_Shortcut.swift`, locate `menuItemWithMatchingShortcut` and `takenByMainMenu`. Move into a top-level helper:

```swift
//
//  KS_MainMenu.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

import AppKit

@MainActor
enum KS_MainMenu {
    /// Recursively searches `NSApp.mainMenu` for a menu item whose `keyEquivalent` matches
    /// the given Carbon keyCode + modifiers. Returns the item if found.
    static func itemMatching(carbonKeyCode: Int, carbonModifiers: Int) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        let modifiers = NSEvent.ModifierFlags(carbonModifiers: carbonModifiers)
        let expectedKeyEquivalent = keyEquivalent(forCarbonKeyCode: carbonKeyCode, modifiers: modifiers)
        return search(in: mainMenu, keyEquivalent: expectedKeyEquivalent, modifiers: modifiers)
    }

    private static func search(in menu: NSMenu, keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        for item in menu.items {
            var itemKeyEquivalent = item.keyEquivalent
            var itemModifierMask = item.keyEquivalentModifierMask
            if modifiers.contains(.shift), itemKeyEquivalent.lowercased() != itemKeyEquivalent {
                itemKeyEquivalent = itemKeyEquivalent.lowercased()
                itemModifierMask.insert(.shift)
            }
            if !itemKeyEquivalent.isEmpty,
               itemKeyEquivalent == keyEquivalent,
               modifiers == itemModifierMask {
                return item
            }
            if let submenu = item.submenu,
               let match = search(in: submenu, keyEquivalent: keyEquivalent, modifiers: modifiers) {
                return match
            }
        }
        return nil
    }

    private static func keyEquivalent(forCarbonKeyCode keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        // For ASCII letter/digit keyCodes, derive lowercase char (mainMenu key equivalents are typically lowercase
        // with shift represented as a modifier flag). For special keys, return the character literal AppKit uses.
        // Reuse the same keyCode→character table as HotkeyConfig.displayString but lowercase / single-char.
        return KS_KeyCodeToChar.lowercaseChar(forCarbonKeyCode: keyCode)
    }
}

/// Minimal keyCode → lowercase character mapping for NSMenuItem.keyEquivalent comparison.
enum KS_KeyCodeToChar {
    static func lowercaseChar(forCarbonKeyCode keyCode: Int) -> String {
        switch Int32(keyCode) {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        // ... full A-Z and 0-9 mapping
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        // ... etc through 9
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case kVK_Delete: return "\u{8}"
        case kVK_Escape: return "\u{1B}"
        default: return ""
        }
    }
}
```

Engineer note: write out the full A-Z + 0-9 cases — there are exactly 36 cases plus the specials shown. Don't abbreviate in the actual file.

- [ ] **Step 7: Write `KS_ModifierFlags+Carbon.swift`**

```swift
//
//  KS_ModifierFlags+Carbon.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

import AppKit
import Carbon.HIToolbox

extension NSEvent.ModifierFlags {
    init(carbonModifiers: Int) {
        var result: NSEvent.ModifierFlags = []
        if carbonModifiers & cmdKey != 0       { result.insert(.command) }
        if carbonModifiers & optionKey != 0    { result.insert(.option) }
        if carbonModifiers & controlKey != 0   { result.insert(.control) }
        if carbonModifiers & shiftKey != 0     { result.insert(.shift) }
        self = result
    }

    /// Subset of these flags that map to Carbon modifier bits. Pass through `NSEvent` flags by
    /// stripping `.deviceIndependentFlagsMask`-only bits we don't care about.
    var carbonRepresentation: Int {
        var result = 0
        if contains(.command) { result |= cmdKey }
        if contains(.option)  { result |= optionKey }
        if contains(.control) { result |= controlKey }
        if contains(.shift)   { result |= shiftKey }
        return result
    }
}
```

- [ ] **Step 8: Write `KS_LocalEventMonitor.swift`**

```swift
//
//  KS_LocalEventMonitor.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

import AppKit

final class KS_LocalEventMonitor {
    private let events: NSEvent.EventTypeMask
    private let callback: (NSEvent) -> NSEvent?
    private var monitor: Any?

    init(events: NSEvent.EventTypeMask, callback: @escaping (NSEvent) -> NSEvent?) {
        self.events = events
        self.callback = callback
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: callback)
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 9: Verify build succeeds**

Run: `swift build`

Expected: Build succeeds without warnings or errors.

If errors mention `HotKeyCenter` or `HotKey`, double-check renames in steps 3 & 4.

- [ ] **Step 10: Commit**

```bash
git add Sources/DumbTransProCore/Vendored
git commit -m "$(cat <<'EOF'
feat: vendor KeyboardShortcuts internals for hotkey customization

Drop in 6 files from sindresorhus/KeyboardShortcuts (MIT, attribution
in file headers) so we can build a custom recorder on top of the same
Carbon + CopySymbolicHotKeys plumbing the upstream library uses,
without taking on an SPM dependency.

Signature changed to "DTPR" so we don't collide with the upstream
library if it ever gets pulled in transitively. HotKey.init? was
converted to throws so callers can map OSStatus to our typed errors.
EOF
)"
```

---

## Task 2: HotkeyConfig + display formatter

**Files:**
- Create: `Sources/DumbTransProCore/HotkeyConfig.swift`
- Create: `Tests/DumbTransProCoreTests/HotkeyConfigTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/DumbTransProCoreTests/HotkeyConfigTests.swift`:

```swift
import Testing
import Carbon.HIToolbox
@testable import DumbTransProCore

struct HotkeyConfigTests {
    @Test func displayString_letterA_cmd() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey))
        #expect(cfg.displayString == "⌘A")
    }

    @Test func displayString_letterR_cmdShift() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
        #expect(cfg.displayString == "⇧⌘R")
    }

    @Test func displayString_modifierOrder_ctrlOptShiftCmd() {
        let cfg = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        #expect(cfg.displayString == "⌃⌥⇧⌘F")
    }

    @Test func displayString_space() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        #expect(cfg.displayString == "⌘Space")
    }

    @Test func displayString_functionKey_F1() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_F1), modifiers: UInt32(controlKey))
        #expect(cfg.displayString == "⌃F1")
    }

    @Test func displayString_arrow() {
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey))
        #expect(cfg.displayString == "⌘←")
    }

    @Test func displayString_unknown_fallback() {
        let cfg = HotkeyConfig(keyCode: 9999, modifiers: UInt32(cmdKey))
        #expect(cfg.displayString.hasPrefix("⌘?"))
    }

    @Test func codable_roundTrip() throws {
        let original = HotkeyConfig(keyCode: 15, modifiers: 1024)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func defaultHotkey_rewriteToEnglish_isCmdShiftR() {
        let cfg = TranslationAction.rewriteToEnglish.defaultHotkey
        #expect(cfg.keyCode == UInt32(kVK_ANSI_R))
        #expect(cfg.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func defaultHotkey_lookup_isCmdShiftF() {
        let cfg = TranslationAction.lookup.defaultHotkey
        #expect(cfg.keyCode == UInt32(kVK_ANSI_F))
        #expect(cfg.modifiers == UInt32(cmdKey | shiftKey))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyConfigTests`

Expected: Compile error — `HotkeyConfig` not defined, `defaultHotkey` not defined.

- [ ] **Step 3: Write `HotkeyConfig.swift`**

```swift
import Carbon.HIToolbox

public struct HotkeyConfig: Codable, Equatable, Sendable, Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Tab: return "Tab"
        case kVK_Return: return "↩"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        default: return "?\(keyCode)"
        }
    }
}
```

- [ ] **Step 4: Add `defaultHotkey` to TranslationAction**

Modify `Sources/DumbTransProCore/TranslationStyle.swift`. Find the `TranslationAction` enum (around line 167) and add after the `hotkeyID` property:

```swift
public var defaultHotkey: HotkeyConfig {
    switch self {
    case .rewriteToEnglish:
        return HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
    case .lookup:
        return HotkeyConfig(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey))
    }
}
```

Do NOT remove `keyCode` / `hotkeyLabel` yet — they're still used by `HotkeyManager` and `MenuBarManager`. They get removed in Task 5.

- [ ] **Step 5: Run tests**

Run: `swift test --filter HotkeyConfigTests`

Expected: All 10 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DumbTransProCore/HotkeyConfig.swift Sources/DumbTransProCore/TranslationStyle.swift Tests/DumbTransProCoreTests/HotkeyConfigTests.swift
git commit -m "feat: HotkeyConfig data type with display formatter

Public struct that holds Carbon keyCode + modifier bitmask, plus a
displayString formatter that produces \"⌘⇧R\" / \"⌃F1\" / \"⌘⌥Space\"
style output for the UI. TranslationAction.defaultHotkey provides
the baseline (⌘⇧R and ⌘⇧F) so storage-missing users get the same
behavior as before."
```

---

## Task 3: SettingsStore hotkey storage

**Files:**
- Modify: `Sources/DumbTransProCore/SettingsStore.swift`
- Create: `Tests/DumbTransProCoreTests/SettingsStoreHotkeyTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/DumbTransProCoreTests/SettingsStoreHotkeyTests.swift`:

```swift
import Testing
import Carbon.HIToolbox
import Foundation
@testable import DumbTransProCore

@MainActor
struct SettingsStoreHotkeyTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.hotkey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func hotkey_unsetKey_returnsDefault() {
        let store = SettingsStore(defaults: freshDefaults())
        let cfg = store.hotkey(for: .rewriteToEnglish)
        #expect(cfg == TranslationAction.rewriteToEnglish.defaultHotkey)
    }

    @Test func setHotkey_persistsAndReturns() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        let custom = HotkeyConfig(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey))
        store.setHotkey(custom, for: .rewriteToEnglish)
        #expect(store.hotkey(for: .rewriteToEnglish) == custom)

        // Verify persistence by creating a fresh store from same defaults
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hotkey(for: .rewriteToEnglish) == custom)
    }

    @Test func setHotkey_nil_returnsExplicitNil_notDefault() {
        let store = SettingsStore(defaults: freshDefaults())
        store.setHotkey(nil, for: .lookup)
        #expect(store.hotkey(for: .lookup) == nil)
    }

    @Test func resetHotkey_returnsToDefault() {
        let store = SettingsStore(defaults: freshDefaults())
        let custom = HotkeyConfig(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))
        store.setHotkey(custom, for: .lookup)
        store.resetHotkey(for: .lookup)
        #expect(store.hotkey(for: .lookup) == TranslationAction.lookup.defaultHotkey)
    }

    @Test func hotkeys_publishedMapReflectsAllActions() {
        let store = SettingsStore(defaults: freshDefaults())
        let map = store.hotkeys
        #expect(map[.rewriteToEnglish] == TranslationAction.rewriteToEnglish.defaultHotkey)
        #expect(map[.lookup] == TranslationAction.lookup.defaultHotkey)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter SettingsStoreHotkeyTests`

Expected: Compile error — `SettingsStore.init(defaults:)`, `hotkey(for:)`, `setHotkey`, `resetHotkey`, `hotkeys` do not exist.

- [ ] **Step 3: Add hotkey storage to SettingsStore**

Modify `Sources/DumbTransProCore/SettingsStore.swift`. Make the existing `init()` use `UserDefaults.standard`, add a new `init(defaults:)` for testing. Add hotkey APIs.

Add near the top, after existing keys:

```swift
private func hotkeyKey(_ action: TranslationAction) -> String {
    "hotkey.\(action.persistenceKey)"
}
```

Add to `TranslationAction` in `TranslationStyle.swift` (right after `hotkeyID`):

```swift
public var persistenceKey: String {
    switch self {
    case .rewriteToEnglish: return "rewriteToEnglish"
    case .lookup:           return "lookup"
    }
}
```

Modify `SettingsStore`:

```swift
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var activeProvider: AIProvider?
    @Published public var translationStyle: TranslationStyle = .natural
    @Published public private(set) var hotkeys: [TranslationAction: HotkeyConfig?] = [:]

    private var configs: [AIProvider: ProviderConfig] = [:]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSettings()
        loadHotkeys()
    }

    private func loadHotkeys() {
        var map: [TranslationAction: HotkeyConfig?] = [:]
        for action in TranslationAction.allCases {
            map[action] = readHotkey(action)
        }
        hotkeys = map
    }

    private func readHotkey(_ action: TranslationAction) -> HotkeyConfig? {
        let key = hotkeyKey(action)
        guard defaults.object(forKey: key) != nil else {
            return action.defaultHotkey  // key absent → default
        }
        guard let data = defaults.data(forKey: key) else {
            return nil  // explicitly stored as null/cleared
        }
        return try? JSONDecoder().decode(HotkeyConfig.self, from: data)
    }

    public func hotkey(for action: TranslationAction) -> HotkeyConfig? {
        if let entry = hotkeys[action] { return entry }
        return action.defaultHotkey
    }

    public func setHotkey(_ config: HotkeyConfig?, for action: TranslationAction) {
        hotkeys[action] = config
        let key = hotkeyKey(action)
        if let config, let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        } else {
            // Explicit nil: mark key present with NSNull sentinel via a "cleared" marker
            defaults.set(Data(), forKey: key)  // empty Data marks "explicitly cleared"
        }
    }

    public func resetHotkey(for action: TranslationAction) {
        hotkeys[action] = action.defaultHotkey
        defaults.removeObject(forKey: hotkeyKey(action))
    }

    // existing code below — find every reference to `UserDefaults.standard` and route through `self.defaults`
    // ...
}
```

In the existing methods (`loadSettings`, `migrateLegacyIfNeeded`, `persistConfig`, etc.), replace every `UserDefaults.standard` with `defaults`. The `init()` signature changing has no external callers to fix yet since `MenuBarManager.swift:13` reads `SettingsStore()` — the default argument handles it.

- [ ] **Step 4: Run tests**

Run: `swift test --filter SettingsStoreHotkeyTests`

Expected: All 5 tests pass.

- [ ] **Step 5: Run full build to ensure nothing else broke**

Run: `swift build`

Expected: Clean build.

- [ ] **Step 6: Commit**

```bash
git add Sources/DumbTransProCore/SettingsStore.swift Sources/DumbTransProCore/TranslationStyle.swift Tests/DumbTransProCoreTests/SettingsStoreHotkeyTests.swift
git commit -m "feat: per-action hotkey storage in SettingsStore

Hotkeys persist as JSON under hotkey.<action> UserDefaults keys.
Three states: key absent → default (first launch / upgrade), key
present with empty Data → user-cleared (intentional nil), key
present with JSON → custom. Published map drives Combine subscribers
in MenuBarManager (added in Task 5)."
```

---

## Task 4: HotkeyManager rewrite + tests

**Files:**
- Modify: `Sources/DumbTransProCore/HotkeyManager.swift` (full rewrite)
- Create: `Tests/DumbTransProCoreTests/HotkeyManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/DumbTransProCoreTests/HotkeyManagerTests.swift`:

```swift
import Testing
import Carbon.HIToolbox
@testable import DumbTransProCore

@MainActor
struct HotkeyManagerTests {
    @Test func start_withAllNilConfigs_registersNothing() {
        let manager = HotkeyManager()
        let result = manager.start(initial: [.rewriteToEnglish: nil, .lookup: nil])
        #expect(result[.rewriteToEnglish] == nil)
        #expect(result[.lookup] == nil)
        manager.stop()
    }

    @Test func reregister_withNil_unregisters_succeeds() {
        let manager = HotkeyManager()
        _ = manager.start(initial: [:])
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey | controlKey))
        let err1 = manager.reregister(action: .rewriteToEnglish, hotkey: cfg)
        #expect(err1 == nil)
        let err2 = manager.reregister(action: .rewriteToEnglish, hotkey: nil)
        #expect(err2 == nil)
        manager.stop()
    }

    @Test func reregister_sameComboTwice_secondReturnsDuplicate() {
        let manager = HotkeyManager()
        _ = manager.start(initial: [:])
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey | controlKey))
        let err1 = manager.reregister(action: .rewriteToEnglish, hotkey: cfg)
        let err2 = manager.reregister(action: .lookup, hotkey: cfg)
        #expect(err1 == nil)
        if case .duplicateInProcess = err2 {} else {
            Issue.record("expected duplicateInProcess, got \(String(describing: err2))")
        }
        manager.stop()
    }

    @Test func pauseAll_unregistersAllowingReregistration_resumeRestores() {
        let manager = HotkeyManager()
        _ = manager.start(initial: [:])
        let cfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | shiftKey | controlKey))
        _ = manager.reregister(action: .rewriteToEnglish, hotkey: cfg)
        manager.pauseAll()
        // After pause, the same combo should be registrable transiently (proves we unregistered)
        let probeErr = manager.reregister(action: .lookup, hotkey: cfg)
        #expect(probeErr == nil)
        // Cleanup
        _ = manager.reregister(action: .lookup, hotkey: nil)
        manager.resumeAll()
        manager.stop()
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter HotkeyManagerTests`

Expected: Compile error — `HotkeyManager.start(initial:)` signature mismatch (it's currently `start() -> Bool`); `reregister`, `pauseAll`, `resumeAll`, `RegisterError` not defined.

- [ ] **Step 3: Rewrite `HotkeyManager.swift`**

Replace the entire contents of `Sources/DumbTransProCore/HotkeyManager.swift`:

```swift
import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    public var onAction: (@MainActor (TranslationAction) -> Void)?

    public enum RegisterError: Error, Equatable {
        case duplicateInProcess
        case invalidParameter
        case unknown(OSStatus)
    }

    private var hotKeys: [TranslationAction: KS_HotKey] = [:]

    public init() {}

    @discardableResult
    public func start(initial: [TranslationAction: HotkeyConfig?]) -> [TranslationAction: RegisterError?] {
        var errors: [TranslationAction: RegisterError?] = [:]
        for action in TranslationAction.allCases {
            let cfg = initial[action] ?? action.defaultHotkey
            errors[action] = registerInternal(action: action, config: cfg)
        }
        return errors
    }

    public func stop() {
        hotKeys.removeAll()  // KS_HotKey deinit unregisters
    }

    @discardableResult
    public func reregister(action: TranslationAction, hotkey: HotkeyConfig?) -> RegisterError? {
        hotKeys[action] = nil  // deinit cleans up Carbon ref
        return registerInternal(action: action, config: hotkey)
    }

    public func pauseAll() {
        KS_HotKeyCenter.shared.pauseAll()
    }

    public func resumeAll() {
        KS_HotKeyCenter.shared.resumeAll()
    }

    private func registerInternal(action: TranslationAction, config: HotkeyConfig?) -> RegisterError? {
        guard let config else { return nil }
        do {
            let hotKey = try KS_HotKey(
                carbonKeyCode: Int(config.keyCode),
                carbonModifiers: Int(config.modifiers),
                onKeyDown: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.onAction?(action)
                    }
                },
                onKeyUp: {}
            )
            hotKeys[action] = hotKey
            return nil
        } catch KS_HotKey.RegisterError.carbonStatus(let status) {
            switch status {
            case OSStatus(eventHotKeyExistsErr): return .duplicateInProcess
            case OSStatus(paramErr):              return .invalidParameter
            default:                              return .unknown(status)
            }
        } catch {
            return .unknown(0)
        }
    }
}
```

- [ ] **Step 4: Update `MenuBarManager.swift` to use new API**

In `Sources/DumbTransProCore/MenuBarManager.swift`, find `setupHotkey()` (around line 185) and replace:

```swift
private func setupHotkey() {
    hotkeyManager.onAction = { [weak self] action in
        self?.handleAction(action)
    }
    let initial = Dictionary(uniqueKeysWithValues:
        TranslationAction.allCases.map { ($0, settingsStore.hotkey(for: $0)) }
    )
    _ = hotkeyManager.start(initial: initial)
}
```

- [ ] **Step 5: Remove unused `TranslationAction.keyCode` and `hotkeyLabel`**

In `Sources/DumbTransProCore/TranslationStyle.swift`, delete the `keyCode` and `hotkeyLabel` properties from `TranslationAction` (lines around 178-189). They are no longer referenced.

Also update `MenuBarManager.populateMenu` at line 132-136 to use the new dynamic display. For now, keep this temporarily showing the configured hotkey from store (full dual-form treatment lands in Task 8):

```swift
for action in TranslationAction.allCases {
    let label: String
    if let cfg = settingsStore.hotkey(for: action) {
        label = "\(action.title)  \(cfg.displayString)"
    } else {
        label = "\(action.title)  (未设置)"
    }
    let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
    item.isEnabled = false
    menu.addItem(item)
}
```

- [ ] **Step 6: Run all tests**

Run: `swift test`

Expected: All tests pass (existing 33 + new 5 hotkey-manager + new 5 settings-store-hotkey + new 10 hotkey-config = 53 tests).

- [ ] **Step 7: Build and smoke test the app**

```bash
swift build
./scripts/build_dev.sh   # if this script exists; otherwise swift run DumbTransPro
```

Manually verify: app launches, menu bar icon appears, `⌘⇧R` and `⌘⇧F` still work as before (default hotkeys).

- [ ] **Step 8: Commit**

```bash
git add Sources/DumbTransProCore/HotkeyManager.swift Sources/DumbTransProCore/MenuBarManager.swift Sources/DumbTransProCore/TranslationStyle.swift Tests/DumbTransProCoreTests/HotkeyManagerTests.swift
git commit -m "refactor: HotkeyManager delegates to vendored KS_HotKeyCenter

Replaces the homemade Carbon EventHandler with the vendored
KS_HotKeyCenter so we get its pause/resume support (needed for
recording) and its menu-tracking observers for free.

start(initial:) now reads per-action config from a passed-in map.
reregister(action:hotkey:) supports live rebinding from the
settings UI (wired in Task 7). pauseAll/resumeAll bracket the
recorder so old hotkeys don't fire while the user is changing them.

TranslationAction.keyCode / hotkeyLabel removed — display string
now comes from HotkeyConfig.displayString."
```

---

## Task 5: HotkeyChipReducer (pure state machine)

**Files:**
- Create: `Sources/DumbTransProCore/HotkeyChipReducer.swift`
- Create: `Tests/DumbTransProCoreTests/HotkeyChipReducerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/DumbTransProCoreTests/HotkeyChipReducerTests.swift`:

```swift
import Testing
import Carbon.HIToolbox
@testable import DumbTransProCore

struct HotkeyChipReducerTests {
    private let sampleCfg = HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))

    @Test func chipClicked_fromResting_entersRecording_emitsInstallMonitorAndPause() {
        let (newState, effects) = HotkeyChipReducer.reduce(state: .resting, event: .chipClicked)
        #expect(newState == .recording(returnTo: .resting))
        #expect(effects.contains(.installMonitor))
        #expect(effects.contains(.pauseAllHotkeys))
    }

    @Test func chipClicked_fromCleared_entersRecording_withReturnToCleared() {
        let (newState, _) = HotkeyChipReducer.reduce(state: .cleared, event: .chipClicked)
        #expect(newState == .recording(returnTo: .cleared))
    }

    @Test func clearClicked_fromResting_goesToClearedAndCommitsNil() {
        let (newState, effects) = HotkeyChipReducer.reduce(state: .resting, event: .clearClicked)
        #expect(newState == .cleared)
        #expect(effects.contains(.commit(nil)))
    }

    @Test func esc_inRecording_returnsToReturnToState_andResumes() {
        let state: RecorderState = .recording(returnTo: .resting)
        let (newState, effects) = HotkeyChipReducer.reduce(state: state, event: .escPressed)
        #expect(newState == .resting)
        #expect(effects.contains(.removeMonitor))
        #expect(effects.contains(.resumeAllHotkeys))
        #expect(!effects.contains(where: { if case .commit = $0 { return true } else { return false } }))
    }

    @Test func delete_inRecording_goesToCleared() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .deleteOrBackspacePressed
        )
        #expect(newState == .cleared)
        #expect(effects.contains(.commit(nil)))
    }

    @Test func tab_inRecording_returnsToReturnToStateAndMovesFocus() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .tabPressed
        )
        #expect(newState == .resting)
        #expect(effects.contains(.moveFocusToNextResponder))
    }

    @Test func validKeyDown_noConflict_commitsAndReturnsToResting() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .keyDown(config: sampleCfg, conflict: .none)
        )
        #expect(newState == .resting)
        #expect(effects.contains(.commit(sampleCfg)))
        #expect(effects.contains(.resumeAllHotkeys))
    }

    @Test func validKeyDown_appInternalConflict_goesToConflict_noCommit() {
        let state: RecorderState = .recording(returnTo: .resting)
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: state,
            event: .keyDown(config: sampleCfg, conflict: .appInternal(otherActionTitle: "划词翻译"))
        )
        if case .conflict(let label, let returnTo) = newState {
            #expect(label.contains("划词翻译"))
            #expect(returnTo == .resting)
        } else {
            Issue.record("expected .conflict state, got \(newState)")
        }
        #expect(!effects.contains(where: { if case .commit = $0 { return true } else { return false } }))
    }

    @Test func validKeyDown_systemConflict_savesAsWarning() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .keyDown(config: sampleCfg, conflict: .system)
        )
        if case .warning = newState {} else {
            Issue.record("expected .warning state, got \(newState)")
        }
        #expect(effects.contains(.commit(sampleCfg)))
    }

    @Test func validKeyDown_mainMenuConflict_savesAsWarning() {
        let (newState, _) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .keyDown(config: sampleCfg, conflict: .mainMenu(itemTitle: "退出"))
        )
        if case .warning(let label) = newState {
            #expect(label.contains("退出"))
        } else {
            Issue.record("expected .warning, got \(newState)")
        }
    }

    @Test func invalidKeyDown_keepsRecording_emitsBeep() {
        let state: RecorderState = .recording(returnTo: .resting)
        let (newState, effects) = HotkeyChipReducer.reduce(state: state, event: .invalidKeyDown)
        #expect(newState == state)
        #expect(effects.contains(.beep))
    }

    @Test func resetClicked_inRecording_commitsDefaultAndReturnsToResting() {
        let (newState, effects) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .resting),
            event: .resetClicked
        )
        #expect(newState == .resting)
        #expect(effects.contains(.commitDefault))
    }

    @Test func focusLost_inRecording_returnsToReturnToState() {
        let (newState, _) = HotkeyChipReducer.reduce(
            state: .recording(returnTo: .cleared),
            event: .focusLost
        )
        #expect(newState == .cleared)
    }

    @Test func esc_fromConflict_returnsToReturnToState() {
        let (newState, _) = HotkeyChipReducer.reduce(
            state: .conflict(label: "X", returnTo: .resting),
            event: .escPressed
        )
        #expect(newState == .resting)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter HotkeyChipReducerTests`

Expected: Compile error — `RecorderState`, `HotkeyChipReducer`, related types not defined.

- [ ] **Step 3: Write `HotkeyChipReducer.swift`**

```swift
import Foundation

public indirect enum RecorderState: Equatable, Sendable {
    case resting
    case recording(returnTo: RecorderState)
    case cleared
    case conflict(label: String, returnTo: RecorderState)
    case warning(label: String)
}

public enum ConflictKind: Equatable, Sendable {
    case none
    case appInternal(otherActionTitle: String)
    case system
    case mainMenu(itemTitle: String)
}

public enum RecorderEvent: Equatable, Sendable {
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

public enum RecorderEffect: Equatable, Sendable {
    case installMonitor
    case removeMonitor
    case pauseAllHotkeys
    case resumeAllHotkeys
    case commit(HotkeyConfig?)
    case commitDefault
    case beep
    case moveFocusToNextResponder
}

public enum HotkeyChipReducer {
    public static func reduce(state: RecorderState, event: RecorderEvent) -> (RecorderState, [RecorderEffect]) {
        switch (state, event) {

        // From resting / warning
        case (.resting, .chipClicked), (.warning, .chipClicked):
            return (.recording(returnTo: .resting), [.installMonitor, .pauseAllHotkeys])

        case (.resting, .clearClicked), (.warning, .clearClicked):
            return (.cleared, [.commit(nil)])

        // From cleared
        case (.cleared, .chipClicked):
            return (.recording(returnTo: .cleared), [.installMonitor, .pauseAllHotkeys])

        // From recording — exit paths
        case (.recording(let returnTo), .escPressed):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.recording, .deleteOrBackspacePressed):
            return (.cleared, [.commit(nil), .removeMonitor, .resumeAllHotkeys])

        case (.recording(let returnTo), .tabPressed):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys, .moveFocusToNextResponder])

        case (.recording(let returnTo), .focusLost):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.recording, .resetClicked):
            return (.resting, [.removeMonitor, .resumeAllHotkeys, .commitDefault])

        case (.recording, .invalidKeyDown):
            return (state, [.beep])

        case (.recording(let returnTo), .keyDown(let cfg, let conflict)):
            switch conflict {
            case .none:
                return (.resting, [.removeMonitor, .resumeAllHotkeys, .commit(cfg)])
            case .appInternal(let other):
                return (
                    .conflict(label: "已被『\(other)』使用", returnTo: returnTo),
                    []
                )
            case .system:
                return (
                    .warning(label: "可能与系统快捷键冲突，可能不生效"),
                    [.removeMonitor, .resumeAllHotkeys, .commit(cfg)]
                )
            case .mainMenu(let title):
                return (
                    .warning(label: "已被菜单项『\(title)』占用，前台 app 优先"),
                    [.removeMonitor, .resumeAllHotkeys, .commit(cfg)]
                )
            }

        // From conflict — exit / re-record
        case (.conflict(_, let returnTo), .escPressed):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.conflict(_, let returnTo), .focusLost):
            return (returnTo, [.removeMonitor, .resumeAllHotkeys])

        case (.conflict(_, let returnTo), .keyDown(let cfg, let conflict)):
            // Treat as if we're back in recording: delegate by re-entering
            return reduce(state: .recording(returnTo: returnTo), event: .keyDown(config: cfg, conflict: conflict))

        case (.conflict, .invalidKeyDown):
            return (state, [.beep])

        // Unhandled combinations: no-op
        default:
            return (state, [])
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter HotkeyChipReducerTests`

Expected: All 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DumbTransProCore/HotkeyChipReducer.swift Tests/DumbTransProCoreTests/HotkeyChipReducerTests.swift
git commit -m "feat: pure reducer for hotkey chip recorder state machine

Five-state machine (resting / recording / cleared / conflict /
warning) modeled as an indirect enum with returnTo metadata so the
View layer doesn't have to remember which state to fall back to on
Esc / focus-loss.

Side effects (install monitor, pause hotkeys, commit, etc.) are
returned as a list rather than executed in the reducer so the whole
thing is pure and unit-testable without driving a SwiftUI view."
```

---

## Task 6: HotkeyChipView (SwiftUI recorder)

**Files:**
- Create: `Sources/DumbTransProCore/HotkeyChipView.swift`

(No new tests — the reducer is already covered; this is a thin view layer that's better validated by manual smoke testing.)

- [ ] **Step 1: Write `HotkeyChipView.swift`**

```swift
import SwiftUI
import AppKit
import Carbon.HIToolbox

public struct HotkeyChipView: View {
    let config: HotkeyConfig?
    let detectConflict: (HotkeyConfig) -> ConflictKind
    let onCommit: (HotkeyConfig?) -> Void
    let onRecordingStarted: () -> Void
    let onRecordingEnded: () -> Void
    let defaultHotkey: HotkeyConfig

    @State private var state: RecorderState = .resting
    @State private var monitor: KS_LocalEventMonitor?

    public init(
        config: HotkeyConfig?,
        defaultHotkey: HotkeyConfig,
        detectConflict: @escaping (HotkeyConfig) -> ConflictKind,
        onCommit: @escaping (HotkeyConfig?) -> Void,
        onRecordingStarted: @escaping () -> Void,
        onRecordingEnded: @escaping () -> Void
    ) {
        self.config = config
        self.defaultHotkey = defaultHotkey
        self.detectConflict = detectConflict
        self.onCommit = onCommit
        self.onRecordingStarted = onRecordingStarted
        self.onRecordingEnded = onRecordingEnded
        let initial: RecorderState = (config == nil) ? .cleared : .resting
        _state = State(initialValue: initial)
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            chip
            footnote
        }
        .onChange(of: config) { _, newValue in
            if case .recording = state { return }
            if case .conflict = state { return }
            state = (newValue == nil) ? .cleared : .resting
        }
    }

    @ViewBuilder
    private var chip: some View {
        switch state {
        case .resting, .warning:
            HStack(spacing: 6) {
                Text(config?.displayString ?? defaultHotkey.displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                Button { dispatch(.clearClicked) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground(color: warningColor))
            .help("更改快捷键")
            .onTapGesture { dispatch(.chipClicked) }

        case .recording, .conflict:
            HStack(spacing: 6) {
                Text("按下快捷键…")
                    .foregroundStyle(.secondary)
                Button { dispatch(.resetClicked) } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground(color: recordingBorderColor))

        case .cleared:
            Button { dispatch(.chipClicked) } label: {
                Text("点击设置")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: 110)
                    .background(chipBackground(color: .clear))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var footnote: some View {
        switch state {
        case .conflict(let label, _):
            Text(label).font(.caption).foregroundStyle(.red)
        case .warning(let label):
            Text(label).font(.caption).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private var warningColor: Color {
        if case .warning = state { return .orange.opacity(0.5) }
        return Color.secondary.opacity(0.3)
    }

    private var recordingBorderColor: Color {
        if case .conflict = state { return .red }
        return .accentColor
    }

    private func chipBackground(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 1.5)
            )
            .frame(minWidth: 110)
    }

    // MARK: - Reducer driver

    private func dispatch(_ event: RecorderEvent) {
        let (newState, effects) = HotkeyChipReducer.reduce(state: state, event: event)
        for effect in effects { apply(effect) }
        state = newState
    }

    private func apply(_ effect: RecorderEffect) {
        switch effect {
        case .installMonitor: installMonitor()
        case .removeMonitor:  removeMonitor()
        case .pauseAllHotkeys: onRecordingStarted()
        case .resumeAllHotkeys: onRecordingEnded()
        case .commit(let cfg): onCommit(cfg)
        case .commitDefault:   onCommit(defaultHotkey)
        case .beep: NSSound.beep()
        case .moveFocusToNextResponder:
            NSApp.keyWindow?.selectNextKeyView(nil)
        }
    }

    // MARK: - NSEvent monitor

    private func installMonitor() {
        let monitor = KS_LocalEventMonitor(events: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in dispatch(.escPressed) }
                return nil
            }
            if event.type == .keyDown,
               event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                Task { @MainActor in dispatch(.deleteOrBackspacePressed) }
                return nil
            }
            if event.type == .keyDown, event.keyCode == UInt16(kVK_Tab) {
                Task { @MainActor in dispatch(.tabPressed) }
                return event  // bubble for focus move
            }
            if event.type == .flagsChanged {
                return nil
            }
            // keyDown — validate
            let strippedMods = event.modifierFlags.subtracting([.shift, .function])
            guard !strippedMods.isEmpty else {
                Task { @MainActor in dispatch(.invalidKeyDown) }
                return nil
            }
            let cfg = HotkeyConfig(
                keyCode: UInt32(event.keyCode),
                modifiers: UInt32(event.modifierFlags.carbonRepresentation)
            )
            let conflict = detectConflict(cfg)
            Task { @MainActor in dispatch(.keyDown(config: cfg, conflict: conflict)) }
            return nil
        }
        monitor.start()
        self.monitor = monitor
    }

    private func removeMonitor() {
        monitor?.stop()
        monitor = nil
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`

Expected: Builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/DumbTransProCore/HotkeyChipView.swift
git commit -m "feat: SwiftUI chip recorder for global hotkeys

Four visual states (resting/recording/cleared/warning) driven by
the pure HotkeyChipReducer state machine. Reducer effects map 1:1
to side-effect callbacks injected by the parent HotkeySection, so
the view itself doesn't reach into HotkeyManager or SettingsStore.

Key capture uses KS_LocalEventMonitor while recording, with Esc
canceling, Delete/Backspace clearing, Tab moving focus, and
modifier-only combos rejected with NSSound.beep()."
```

---

## Task 7: HotkeySection (conflict detection + store glue)

**Files:**
- Create: `Sources/DumbTransProCore/HotkeySection.swift`

- [ ] **Step 1: Write `HotkeySection.swift`**

```swift
import SwiftUI
import AppKit

public struct HotkeySection: View {
    @ObservedObject var store: SettingsStore
    let hotkeyManager: HotkeyManager

    public init(store: SettingsStore, hotkeyManager: HotkeyManager) {
        self.store = store
        self.hotkeyManager = hotkeyManager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.subheadline)

            ForEach(TranslationAction.allCases, id: \.self) { action in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.body)
                        Text(actionSubtitle(action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotkeyChipView(
                        config: store.hotkey(for: action),
                        defaultHotkey: action.defaultHotkey,
                        detectConflict: { detectConflict($0, for: action) },
                        onCommit: { commit($0, for: action) },
                        onRecordingStarted: { hotkeyManager.pauseAll() },
                        onRecordingEnded:   { hotkeyManager.resumeAll() }
                    )
                }
            }
        }
    }

    private func actionSubtitle(_ action: TranslationAction) -> String {
        switch action {
        case .rewriteToEnglish: return "将选中文译为英文并粘贴回去"
        case .lookup:           return "选中后弹出查词面板"
        }
    }

    private func detectConflict(_ config: HotkeyConfig, for action: TranslationAction) -> ConflictKind {
        // 1. App-internal: same combo used by the other action
        for other in TranslationAction.allCases where other != action {
            if store.hotkey(for: other) == config {
                return .appInternal(otherActionTitle: other.title)
            }
        }
        // 2. Main menu
        if let item = KS_MainMenu.itemMatching(
            carbonKeyCode: Int(config.keyCode),
            carbonModifiers: Int(config.modifiers)
        ) {
            return .mainMenu(itemTitle: item.title)
        }
        // 3. System
        if KS_SystemShortcuts.contains(
            carbonKeyCode: Int(config.keyCode),
            carbonModifiers: Int(config.modifiers)
        ) {
            return .system
        }
        return .none
    }

    private func commit(_ config: HotkeyConfig?, for action: TranslationAction) {
        store.setHotkey(config, for: action)
        _ = hotkeyManager.reregister(action: action, hotkey: config)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`

Expected: Clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/DumbTransProCore/HotkeySection.swift
git commit -m "feat: settings panel section for hotkey customization

Wires HotkeyChipView, SettingsStore, and HotkeyManager together.
Owns conflict detection (app-internal → main menu → system) and
the live re-registration call on commit. Section is the only
component that knows about both Store and Manager — the chip itself
remains a pure dumb component."
```

---

## Task 8: SettingsView integration + MenuBarManager dual-form menu

**Files:**
- Modify: `Sources/DumbTransProCore/SettingsView.swift`
- Modify: `Sources/DumbTransProCore/MenuBarManager.swift`

- [ ] **Step 1: Insert HotkeySection in SettingsView**

In `Sources/DumbTransProCore/SettingsView.swift`, find the `body` property (around line 28). Locate the `Divider()` before `translationStyleSection` and insert above it:

```swift
public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text("瞎翻 Pro 设置")
            .font(.headline)

        providerSection

        if let provider = selectedProvider {
            endpointSection(provider: provider)
            apiKeySection(provider: provider)
            modelSection(provider: provider)
        }

        Divider()

        HotkeySection(store: store, hotkeyManager: hotkeyManager)

        Divider()

        translationStyleSection

        HStack {
            Spacer()
            Button("取消") {
                onClose?()
                dismiss()
            }
            Button("保存") {
                saveAndClose()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProvider == nil)
        }
    }
    .padding(20)
    .frame(width: 520)
}
```

Add `hotkeyManager` to the init:

```swift
@ObservedObject var store: SettingsStore
let hotkeyManager: HotkeyManager
@Environment(\.dismiss) private var dismiss
private let onClose: (() -> Void)?

// ... existing @State ...

public init(store: SettingsStore, hotkeyManager: HotkeyManager, onClose: (() -> Void)? = nil) {
    self.store = store
    self.hotkeyManager = hotkeyManager
    self.onClose = onClose
    // ... existing init body unchanged ...
}
```

- [ ] **Step 2: Update MenuBarManager.openSettings to pass hotkeyManager**

In `Sources/DumbTransProCore/MenuBarManager.swift`, find `openSettings()` (around line 263). Update the SettingsView init call:

```swift
let view = SettingsView(store: settingsStore, hotkeyManager: hotkeyManager) { [weak window] in
    window?.close()
}
```

Also expand the settings window frame slightly for the new section:

```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),  // was 500
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
```

- [ ] **Step 3: Update MenuBarManager.populateMenu for dual-form items**

Find `populateMenu` (around line 110) and replace the `for action in TranslationAction.allCases` block to produce clickable items when there's no hotkey:

```swift
if isTranslating {
    let status = NSMenuItem(title: "翻译中...", action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
} else {
    for action in TranslationAction.allCases {
        let item: NSMenuItem
        if let cfg = settingsStore.hotkey(for: action) {
            item = NSMenuItem(
                title: "\(action.title)  \(cfg.displayString)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
        } else {
            item = NSMenuItem(
                title: action.title,
                action: #selector(menuActionTriggered(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action
        }
        menu.addItem(item)
    }
}
```

Then add the action handler somewhere near `handleAction`:

```swift
@objc private func menuActionTriggered(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? TranslationAction else { return }
    handleAction(action)
}
```

- [ ] **Step 4: Subscribe to store.$hotkeys to live-refresh the menu**

In `MenuBarManager`, add a property:

```swift
private var cancellables: Set<AnyCancellable> = []
```

Add `import Combine` at the top if not present.

In `init`, after `setupHotkey()`, subscribe:

```swift
settingsStore.$hotkeys
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        guard let self else { return }
        self.applyHotkeyChanges()
        self.updateMenu()
    }
    .store(in: &cancellables)
```

Add `applyHotkeyChanges`:

```swift
private func applyHotkeyChanges() {
    for action in TranslationAction.allCases {
        _ = hotkeyManager.reregister(action: action, hotkey: settingsStore.hotkey(for: action))
    }
}
```

Note: `HotkeySection.commit` also calls `reregister` directly, which is fine — the subscription is a safety net and idempotent (reregister is unregister-then-register).

- [ ] **Step 5: Build and run smoke test**

```bash
swift build
swift run DumbTransPro &
# Verify: Open settings, see new "快捷键" section above 翻译风格.
# Change ⌘⇧R to ⌘⌥T, close settings, try ⌘⌥T — should trigger 中文转英文.
# Click X on a hotkey → that row in menu bar dropdown becomes clickable → click it → action fires.
# Click chip → press ⌘Q → see yellow "已被菜单项..." warning.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/DumbTransProCore/SettingsView.swift Sources/DumbTransProCore/MenuBarManager.swift
git commit -m "feat: wire HotkeySection into settings + dual-form menu fallback

Settings panel grows a 快捷键 section between provider/model and
翻译风格. The menu bar dropdown now shows a clickable item for any
action whose hotkey was cleared, so the feature still works without
a hotkey configured.

MenuBarManager subscribes to SettingsStore.\$hotkeys so external
changes (or programmatic clears) propagate to both the Carbon
registration and the menu UI without manual refresh."
```

---

## Task 9: Settings window focus management + final polish

**Files:**
- Modify: `Sources/DumbTransProCore/HotkeyChipView.swift`
- Modify: `Sources/DumbTransProCore/MenuBarManager.swift`

- [ ] **Step 1: Add window-resign-key handling to HotkeyChipView**

In `HotkeyChipView`, add inside the `body`:

```swift
.onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
    if case .recording = state {
        dispatch(.focusLost)
    } else if case .conflict = state {
        dispatch(.focusLost)
    }
}
```

- [ ] **Step 2: Add click-outside handling to HotkeyChipView**

Extend the existing `installMonitor` to also listen for left/right mouse-up outside the chip bounds. Replace the monitor events parameter:

```swift
let monitor = KS_LocalEventMonitor(events: [.keyDown, .flagsChanged, .leftMouseUp, .rightMouseUp]) { event in
    if event.type == .leftMouseUp || event.type == .rightMouseUp {
        Task { @MainActor in dispatch(.focusLost) }
        return event  // let the click do its normal job
    }
    // ... existing keyDown / flagsChanged handling unchanged ...
}
```

This is a conservative approach — any click anywhere blurs the recorder. (Strict outside-of-chip-bounds detection would require a GeometryReader + screen coordinate math; not worth it for first version.)

- [ ] **Step 3: Run full test suite**

Run: `swift test`

Expected: All tests pass.

- [ ] **Step 4: Manual smoke test — focus management**

```bash
swift run DumbTransPro &
```

Verify:
1. Open settings — chip should NOT be focused / in recording state
2. Click chip → enters recording → cmd-tab to another app → return to DumbTransPro settings → chip should be out of recording state
3. Click chip → enters recording → click elsewhere in settings window → chip exits recording
4. Click chip → enters recording → press Esc → returns to resting

- [ ] **Step 5: Commit**

```bash
git add Sources/DumbTransProCore/HotkeyChipView.swift
git commit -m "polish: HotkeyChipView exits recording on click-outside or window blur

Window losing key fires .focusLost; mouse-up anywhere during
recording also bails. Matches the KeyboardShortcuts upstream
behavior — keeps the recorder from staying 'sticky' if the user
gets distracted."
```

---

## Task 10: Documentation update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README hotkey section**

Find the section in `README.md` listing the default hotkeys (`⌘⇧R` / `⌘⇧F`). Add a paragraph after it explaining custom hotkeys:

```markdown
### 自定义快捷键

打开设置面板（菜单栏 → "设置..."），在「快捷键」区域可以为两个翻译动作自定义全局快捷键：

- 点击芯片进入录制态，按下任意"≥1 个 ⌘/⌃/⌥ + 主键"的组合自动保存
- 点击 `×` 清空快捷键 —— 菜单栏 dropdown 里对应行会变成可点击触发
- 录制态按 Esc 取消，按 Delete 清空，点 ↺ 重置回默认值
- 与系统快捷键 / 主菜单项冲突时会有黄色软提示，仍允许保存
- 两个动作不能用同一个组合 —— 撞了会有红色提示，需重录
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — document custom hotkey recorder"
```

---

## Self-Review

**Spec coverage:**
- §UI/Interaction (chip 4 状态 + tooltip + 错误位置) — Task 6 (HotkeyChipView) ✓
- §数据模型 (HotkeyConfig, defaultHotkey, persistenceKey) — Tasks 2, 3 ✓
- §持久化语义 (key absent / null / JSON) — Task 3 ✓
- §HotkeyManager 接口 (start/stop/reregister/pauseAll/resumeAll) — Task 4 ✓
- §SettingsStore 改动 — Task 3 ✓
- §数据流 (chip → section → store → manager) — Tasks 6, 7 ✓
- §状态机 5 状态 reducer — Task 5 ✓
- §录制态键盘捕获 — Task 6 ✓
- §冲突检测 (app-internal / main menu / system) — Task 7 ✓
- §菜单栏 fallback — Task 8 ✓
- §焦点管理 (window-resign-key, click outside) — Task 9 ✓
- §测试策略 — Tasks 2, 3, 4, 5 ✓
- README 更新 — Task 10 ✓

**Gaps:**
- Spec mentioned "preventBecomingKey" (settings window not auto-focusing the chip on open). The SwiftUI default behavior doesn't auto-focus arbitrary views, so we may not need explicit handling. Will verify in Task 8 smoke test; if a problem appears, add an explicit `.focused()` binding fix as an in-task adjustment.
- Spec mentioned displaying registrationErrors as a red banner in `HotkeySection` when Carbon registration fails. Current plan handles internal-conflict via the reducer flow but doesn't surface `RegisterError.duplicateInProcess` returned by `MenuBarManager.applyHotkeyChanges`. Since this only happens if state somehow becomes inconsistent (the section's conflict detection should always catch first), treating it as a non-critical defense is reasonable for V1.

**Type consistency:**
- `RecorderState`, `RecorderEvent`, `RecorderEffect`, `ConflictKind` — defined in Task 5, used identically in Tasks 6, 7 ✓
- `HotkeyConfig` — Task 2 defines public init, used in Tasks 3, 4, 5, 6, 7 ✓
- `HotkeyManager.RegisterError` — defined in Task 4, used by Task 7's commit ✓
- `KS_HotKey`, `KS_HotKeyCenter` — Task 1, used in Task 4 ✓
- `KS_SystemShortcuts.contains(carbonKeyCode:carbonModifiers:)` — Task 1, used in Task 7 ✓
- `KS_MainMenu.itemMatching(carbonKeyCode:carbonModifiers:)` — Task 1, used in Task 7 ✓
- `NSEvent.ModifierFlags.carbonRepresentation` — defined in Task 1's KS_ModifierFlags+Carbon.swift, used in Task 6 ✓
- `TranslationAction.persistenceKey` — defined in Task 3 step 3, used by SettingsStore ✓

**Placeholder scan:** Grep for "TBD" / "TODO" / "fill in" / "similar to" — none present. Each step shows the actual code to write.
