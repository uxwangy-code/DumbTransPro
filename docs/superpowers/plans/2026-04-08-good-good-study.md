# good-good-study Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menubar app that translates selected Chinese text into kebab-case English filenames via OpenAI API, triggered by a global hotkey.

**Architecture:** SPM executable target for the app, SPM library target (`GoodGoodStudyCore`) for testable business logic. Shell script packages the binary into a .app bundle with Info.plist and entitlements. CGEventTap for global hotkey, NSPasteboard for clipboard, URLSession for API calls.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, SPM, OpenAI API (GPT-4o mini)

---

## File Structure

```
good-good-study/
├── Package.swift                          # SPM manifest: 2 targets (app + core lib) + test target
├── Sources/
│   ├── GoodGoodStudy/
│   │   └── main.swift                     # App entry point, NSApplication setup
│   └── GoodGoodStudyCore/
│       ├── MenuBarManager.swift           # NSStatusItem lifecycle + menu
│       ├── HotkeyManager.swift            # CGEventTap global hotkey
│       ├── TranslateService.swift         # OpenAI API call + response parsing
│       ├── TextFormatter.swift            # kebab-case formatting logic
│       ├── ClipboardManager.swift         # NSPasteboard read/write + simulate paste
│       ├── KeychainHelper.swift           # Keychain CRUD for API key
│       ├── SettingsView.swift             # SwiftUI settings window
│       └── SettingsStore.swift            # UserDefaults wrapper
├── Tests/
│   └── GoodGoodStudyCoreTests/
│       ├── TextFormatterTests.swift       # kebab-case formatting tests
│       ├── TranslateServiceTests.swift    # API request/response parsing tests
│       └── KeychainHelperTests.swift      # Keychain read/write tests
├── Resources/
│   ├── Info.plist                         # LSUIElement = true
│   └── GoodGoodStudy.entitlements         # Accessibility entitlement
├── scripts/
│   └── bundle.sh                          # Build + package into .app
└── docs/
```

---

### Task 1: SPM 项目骨架 + 空壳运行

**Files:**
- Create: `Package.swift`
- Create: `Sources/GoodGoodStudy/main.swift`
- Create: `Sources/GoodGoodStudyCore/TextFormatter.swift` (placeholder export)
- Create: `Resources/Info.plist`
- Create: `Resources/GoodGoodStudy.entitlements`
- Create: `scripts/bundle.sh`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoodGoodStudy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "GoodGoodStudyCore"
        ),
        .executableTarget(
            name: "GoodGoodStudy",
            dependencies: ["GoodGoodStudyCore"]
        ),
        .testTarget(
            name: "GoodGoodStudyCoreTests",
            dependencies: ["GoodGoodStudyCore"]
        ),
    ]
)
```

- [ ] **Step 2: Create main.swift — minimal NSApplication menubar app**

```swift
import AppKit
import GoodGoodStudyCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create MenuBarManager.swift — minimal status item**

```swift
import AppKit

@MainActor
public class MenuBarManager {
    private var statusItem: NSStatusItem?

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "好"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
}
```

- [ ] **Step 4: Create TextFormatter.swift — placeholder**

```swift
import Foundation

public enum TextFormatter {
    public static func toKebabCase(_ input: String) -> String {
        return input
    }
}
```

- [ ] **Step 5: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>GoodGoodStudy</string>
    <key>CFBundleIdentifier</key>
    <string>com.whimsycode.good-good-study</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleExecutable</key>
    <string>GoodGoodStudy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
```

- [ ] **Step 6: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 7: Create bundle.sh**

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/build/GoodGoodStudy.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "Building..."
cd "$PROJECT_DIR"
swift build -c release

echo "Packaging..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BUILD_DIR/GoodGoodStudy" "$MACOS_DIR/"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/"

echo "Done: $APP_DIR"
```

- [ ] **Step 8: Build and verify**

Run: `cd /Users/thirty/myproject/good-good-study && swift build 2>&1`
Expected: Build succeeds with no errors.

- [ ] **Step 9: Commit**

```bash
git init
git add Package.swift Sources/ Resources/ scripts/ docs/
git commit -m "feat: SPM project skeleton with menubar app shell"
```

---

### Task 2: TextFormatter — kebab-case 格式化逻辑 (TDD)

**Files:**
- Modify: `Sources/GoodGoodStudyCore/TextFormatter.swift`
- Create: `Tests/GoodGoodStudyCoreTests/TextFormatterTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import GoodGoodStudyCore

struct TextFormatterTests {
    @Test func basicKebabCase() {
        #expect(TextFormatter.toKebabCase("hello world") == "hello-world")
    }

    @Test func uppercaseToLower() {
        #expect(TextFormatter.toKebabCase("Hello World") == "hello-world")
    }

    @Test func removePunctuation() {
        #expect(TextFormatter.toKebabCase("hello, world!") == "hello-world")
    }

    @Test func collapseSpaces() {
        #expect(TextFormatter.toKebabCase("hello   world") == "hello-world")
    }

    @Test func trimEdges() {
        #expect(TextFormatter.toKebabCase("  hello world  ") == "hello-world")
    }

    @Test func preserveNumbers() {
        #expect(TextFormatter.toKebabCase("project 2024") == "project-2024")
    }

    @Test func alreadyKebab() {
        #expect(TextFormatter.toKebabCase("already-kebab") == "already-kebab")
    }

    @Test func emptyString() {
        #expect(TextFormatter.toKebabCase("") == "")
    }

    @Test func chinesePassthrough() {
        // Chinese characters should pass through (they'll come pre-translated from AI)
        #expect(TextFormatter.toKebabCase("good good study") == "good-good-study")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/thirty/myproject/good-good-study && swift test --filter TextFormatterTests 2>&1`
Expected: Tests fail (toKebabCase just returns input unchanged).

- [ ] **Step 3: Implement TextFormatter**

```swift
import Foundation

public enum TextFormatter {
    public static func toKebabCase(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        let lowered = trimmed.lowercased()
        // Keep only alphanumeric, spaces, and hyphens
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return Character(scalar)
            } else {
                return " "
            }
        }
        let joined = String(cleaned)
        // Split on whitespace, filter empty, join with hyphens
        let parts = joined.split(separator: " ", omittingEmptySubsequences: true)
        return parts.joined(separator: "-")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/thirty/myproject/good-good-study && swift test --filter TextFormatterTests 2>&1`
Expected: All 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoodGoodStudyCore/TextFormatter.swift Tests/
git commit -m "feat: TextFormatter kebab-case logic with tests"
```

---

### Task 3: KeychainHelper — API Key 安全存储 (TDD)

**Files:**
- Create: `Sources/GoodGoodStudyCore/KeychainHelper.swift`
- Create: `Tests/GoodGoodStudyCoreTests/KeychainHelperTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import GoodGoodStudyCore

struct KeychainHelperTests {
    private let testService = "com.whimsycode.good-good-study.test"
    private let testAccount = "api-key-test"

    @Test func saveAndRetrieve() throws {
        let key = "sk-test-\(UUID().uuidString.prefix(8))"
        try KeychainHelper.save(service: testService, account: testAccount, data: key)
        let retrieved = try KeychainHelper.load(service: testService, account: testAccount)
        #expect(retrieved == key)
        // Cleanup
        try KeychainHelper.delete(service: testService, account: testAccount)
    }

    @Test func loadNonExistent() {
        let result = try? KeychainHelper.load(service: testService, account: "nonexistent-\(UUID())")
        #expect(result == nil)
    }

    @Test func overwrite() throws {
        let key1 = "sk-first"
        let key2 = "sk-second"
        try KeychainHelper.save(service: testService, account: testAccount, data: key1)
        try KeychainHelper.save(service: testService, account: testAccount, data: key2)
        let retrieved = try KeychainHelper.load(service: testService, account: testAccount)
        #expect(retrieved == key2)
        try KeychainHelper.delete(service: testService, account: testAccount)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/thirty/myproject/good-good-study && swift test --filter KeychainHelperTests 2>&1`
Expected: Compilation error — KeychainHelper doesn't exist yet.

- [ ] **Step 3: Implement KeychainHelper**

```swift
import Foundation
import Security

public enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
}

public enum KeychainHelper {
    public static func save(service: String, account: String, data: String) throws {
        guard let encoded = data.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        // Delete existing item first
        try? delete(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: encoded,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public static func load(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        return string
    }

    public static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/thirty/myproject/good-good-study && swift test --filter KeychainHelperTests 2>&1`
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoodGoodStudyCore/KeychainHelper.swift Tests/GoodGoodStudyCoreTests/KeychainHelperTests.swift
git commit -m "feat: KeychainHelper for secure API key storage with tests"
```

---

### Task 4: TranslateService — OpenAI API 调用 (TDD)

**Files:**
- Create: `Sources/GoodGoodStudyCore/TranslateService.swift`
- Create: `Tests/GoodGoodStudyCoreTests/TranslateServiceTests.swift`

- [ ] **Step 1: Write failing tests (mock URLProtocol for network isolation)**

```swift
import Testing
import Foundation
@testable import GoodGoodStudyCore

// Mock URL protocol for testing
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockResponseData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200
    nonisolated(unsafe) static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.mockResponseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct TranslateServiceTests {
    func makeTestSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func successfulTranslation() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "good good study"
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习")
        #expect(result == "good-good-study")
    }

    @Test func apiErrorReturnsError() async {
        MockURLProtocol.mockStatusCode = 401
        MockURLProtocol.mockResponseData = """
        {"error":{"message":"Invalid API key"}}
        """.data(using: .utf8)

        let service = TranslateService(apiKey: "bad-key", session: makeTestSession())
        do {
            _ = try await service.translate("测试")
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is TranslateError)
        }
    }

    @Test func responseWithWhitespace() async throws {
        let responseJSON = """
        {
          "choices": [{
            "message": {
              "content": "  Good Good Study  "
            }
          }]
        }
        """
        MockURLProtocol.mockResponseData = responseJSON.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = TranslateService(apiKey: "sk-test", session: makeTestSession())
        let result = try await service.translate("好好学习")
        #expect(result == "good-good-study")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/thirty/myproject/good-good-study && swift test --filter TranslateServiceTests 2>&1`
Expected: Compilation error — TranslateService doesn't exist yet.

- [ ] **Step 3: Implement TranslateService**

```swift
import Foundation

public enum TranslateError: Error, LocalizedError {
    case noAPIKey
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API Key 未设置"
        case .apiError(let code, let msg): return "API 错误 (\(code)): \(msg)"
        case .invalidResponse: return "无效的 API 响应"
        case .networkError(let err): return "网络错误: \(err.localizedDescription)"
        }
    }
}

public final class TranslateService: Sendable {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func translate(_ text: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        将以下中文逐字直译成英文，用空格分隔，全小写，不要意译，不要优化，不要加标点。只输出翻译结果，不要其他内容。
        输入：\(text)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0,
            "max_tokens": 100,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            throw TranslateError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslateError.invalidResponse
        }

        return TextFormatter.toKebabCase(content)
    }

    private func parseErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "Unknown error"
        }
        return message
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/thirty/myproject/good-good-study && swift test --filter TranslateServiceTests 2>&1`
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GoodGoodStudyCore/TranslateService.swift Tests/GoodGoodStudyCoreTests/TranslateServiceTests.swift
git commit -m "feat: TranslateService with OpenAI API integration and tests"
```

---

### Task 5: ClipboardManager — 剪贴板读写 + 模拟粘贴

**Files:**
- Create: `Sources/GoodGoodStudyCore/ClipboardManager.swift`

- [ ] **Step 1: Implement ClipboardManager**

Note: Clipboard and CGEvent simulation are system-level operations that don't lend themselves to unit testing. We verify manually.

```swift
import AppKit
import Carbon.HIToolbox

@MainActor
public enum ClipboardManager {
    /// Read currently selected text by simulating Cmd+C, waiting, then reading pasteboard.
    public static func getSelectedText() async -> String? {
        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        // Simulate Cmd+C
        simulateKeyPress(keyCode: UInt16(kVK_ANSI_C), flags: .maskCommand)

        // Wait for pasteboard to update
        try? await Task.sleep(for: .milliseconds(100))

        let newText: String?
        if pasteboard.changeCount != oldChangeCount {
            newText = pasteboard.string(forType: .string)
        } else {
            newText = nil
        }

        // Restore old pasteboard contents
        if let old = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }

        return newText
    }

    /// Write text to pasteboard and simulate Cmd+V to paste.
    public static func pasteText(_ text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(for: .milliseconds(50))

        simulateKeyPress(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
    }

    private static func simulateKeyPress(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/thirty/myproject/good-good-study && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoodGoodStudyCore/ClipboardManager.swift
git commit -m "feat: ClipboardManager with clipboard read/write and key simulation"
```

---

### Task 6: HotkeyManager — 全局快捷键监听

**Files:**
- Create: `Sources/GoodGoodStudyCore/HotkeyManager.swift`

- [ ] **Step 1: Implement HotkeyManager**

```swift
import AppKit

@MainActor
public final class HotkeyManager {
    public var onHotkey: (@MainActor () -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    public func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // Store self reference for the C callback
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags

                    // ⌘+Shift+T: keyCode 17 = T
                    let hasCmd = flags.contains(.maskCommand)
                    let hasShift = flags.contains(.maskShift)
                    let noOption = !flags.contains(.maskAlternate)
                    let noCtrl = !flags.contains(.maskControl)

                    if keyCode == 17 && hasCmd && hasShift && noOption && noCtrl {
                        DispatchQueue.main.async {
                            manager.onHotkey?()
                        }
                        return nil // Consume the event
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        // Note: stop() must be called on MainActor before deinit
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/thirty/myproject/good-good-study && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/GoodGoodStudyCore/HotkeyManager.swift
git commit -m "feat: HotkeyManager with CGEventTap for global Cmd+Shift+T"
```

---

### Task 7: SettingsStore + SettingsView — 设置界面

**Files:**
- Create: `Sources/GoodGoodStudyCore/SettingsStore.swift`
- Create: `Sources/GoodGoodStudyCore/SettingsView.swift`

- [ ] **Step 1: Implement SettingsStore**

```swift
import Foundation

private let keychainService = "com.whimsycode.good-good-study"
private let keychainAccount = "openai-api-key"

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var apiKey: String = ""

    public init() {
        loadAPIKey()
    }

    public func loadAPIKey() {
        apiKey = (try? KeychainHelper.load(service: keychainService, account: keychainAccount)) ?? ""
    }

    public func saveAPIKey() {
        if apiKey.isEmpty {
            try? KeychainHelper.delete(service: keychainService, account: keychainAccount)
        } else {
            try? KeychainHelper.save(service: keychainService, account: keychainAccount, data: apiKey)
        }
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
```

- [ ] **Step 2: Implement SettingsView**

```swift
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("good-good-study 设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.subheadline)
                SecureField("sk-...", text: $store.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
            }

            HStack {
                Spacer()
                Button("取消") {
                    store.loadAPIKey()
                    dismiss()
                }
                Button("保存") {
                    store.saveAPIKey()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/thirty/myproject/good-good-study && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/GoodGoodStudyCore/SettingsStore.swift Sources/GoodGoodStudyCore/SettingsView.swift
git commit -m "feat: settings UI with API key management"
```

---

### Task 8: 整合所有模块 — 完整工作流

**Files:**
- Modify: `Sources/GoodGoodStudyCore/MenuBarManager.swift`
- Modify: `Sources/GoodGoodStudy/main.swift`

- [ ] **Step 1: Update MenuBarManager to wire everything together**

Replace `Sources/GoodGoodStudyCore/MenuBarManager.swift` entirely:

```swift
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
        setupStatusItem()
        setupHotkey()
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
            showNotification(title: "good-good-study", message: "无法注册全局快捷键，请在系统设置中授予辅助功能权限。")
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
            let service = TranslateService(apiKey: settingsStore.apiKey)
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
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
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }
}
```

- [ ] **Step 2: main.swift stays the same — verify build**

Run: `cd /Users/thirty/myproject/good-good-study && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 3: Run all tests**

Run: `cd /Users/thirty/myproject/good-good-study && swift test 2>&1`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: wire all modules together in MenuBarManager"
```

---

### Task 9: 打包脚本 + 手动验证

**Files:**
- Modify: `scripts/bundle.sh` (already created in Task 1, make executable)

- [ ] **Step 1: Make bundle.sh executable and run**

Run: `chmod +x /Users/thirty/myproject/good-good-study/scripts/bundle.sh && /Users/thirty/myproject/good-good-study/scripts/bundle.sh 2>&1`
Expected: `Done: /Users/thirty/myproject/good-good-study/build/GoodGoodStudy.app`

- [ ] **Step 2: Verify app bundle structure**

Run: `ls -la /Users/thirty/myproject/good-good-study/build/GoodGoodStudy.app/Contents/ && ls -la /Users/thirty/myproject/good-good-study/build/GoodGoodStudy.app/Contents/MacOS/`
Expected: Info.plist in Contents/, GoodGoodStudy binary in MacOS/.

- [ ] **Step 3: Launch app for manual test**

Run: `open /Users/thirty/myproject/good-good-study/build/GoodGoodStudy.app`
Expected: "好" appears in macOS menubar. Clicking shows menu with settings option.

- [ ] **Step 4: Commit**

```bash
git add scripts/
git commit -m "feat: bundle script for packaging .app"
```

---

### Task 10: .gitignore + 项目收尾

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```
.build/
build/
.swiftpm/
*.xcodeproj
xcuserdata/
DerivedData/
.DS_Store
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore"
```
