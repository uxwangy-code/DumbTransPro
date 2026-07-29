import Foundation

/// 离线翻译引擎的抽象。调用方（路由层）只依赖这个协议，不直接碰 macOS 15 的
/// Translation 类型——这样路由逻辑可在任意系统上编译，并能用假引擎做单测。
@MainActor
public protocol OfflineTranslating: AnyObject {
    /// 中 → 英（「用中文写英文」的离线兜底）。返回纯英文，kebab/分流由路由层处理。
    func rewriteToEnglish(_ text: String) async throws -> String
    /// 英 → 简体中文（划词翻译的离线路径）。
    func lookupToChinese(_ text: String) async throws -> String
    /// 当前中↔英语言包状态，供路由层判断「可直接用 / 需下载 / 不支持」。
    func availability() async -> OfflineAvailability
}

public enum OfflineAvailability: Sendable, Equatable {
    case ready          // 语言包已安装，可直接离线翻译
    case needsDownload  // 系统支持但语言包未下载（首次需引导下载）
    case unsupported    // 系统不支持（理论上 macOS 15+ 都支持中英）
}

public enum OfflineTranslateError: Error, LocalizedError, Equatable {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let msg): return "离线翻译失败：\(msg)"
        }
    }
}

#if canImport(Translation)
import AppKit
import SwiftUI
@preconcurrency import Translation

/// 基于 Apple Translation framework 的设备端离线翻译（macOS 15+）。
///
/// Apple 只通过 SwiftUI 的 `.translationTask` 修饰符交付 `TranslationSession`，
/// 所以这里挂一个隐藏离屏的 SwiftUI host，常驻两个 session（中→英 改写 / 英→中
/// 划词）。`TranslationSession.translate` 是 nonisolated 的，所以 session 必须留在
/// translationTask 闭包（无 actor 隔离域）里使用；跨到主 actor 只传 Sendable 数据
/// （id / 文本 / 结果字符串），continuation 按 id 存在主 actor 字典、在主 actor 上 resume。
/// 该模式经 v1.4 Phase 0 spike 验证（`/tmp/spike-host`）。
///
/// 整型 `@available(macOS 15)`；13/14 上 Translation 被弱链接、永不触达
/// （调用方先查可用性再决定是否创建本服务）。
@available(macOS 15, *)
@MainActor
public final class AppleTranslationService: OfflineTranslating {

    fileprivate enum Direction { case zhToEn, enToZh }
    fileprivate struct WorkItem: Sendable { let id: UUID; let text: String }
    fileprivate enum Outcome: Sendable { case success(String); case failure(String) }

    // 「有新请求」信号流：只走 Void（Sendable）。nonisolated let 便于无隔离的
    // translationTask 闭包直接消费，无需 await 主 actor。
    fileprivate nonisolated let zhToEnSignal: AsyncStream<Void>
    private nonisolated let zhToEnSignalCont: AsyncStream<Void>.Continuation
    fileprivate nonisolated let enToZhSignal: AsyncStream<Void>
    private nonisolated let enToZhSignalCont: AsyncStream<Void>.Continuation

    // 主 actor 状态：continuation 按 id 存放，从不穿过 actor 边界。
    private var continuations: [UUID: CheckedContinuation<String, Error>] = [:]
    private var pendingZhToEn: [WorkItem] = []
    private var pendingEnToZh: [WorkItem] = []

    private var window: NSWindow?

    public init() {
        (zhToEnSignal, zhToEnSignalCont) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (enToZhSignal, enToZhSignalCont) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        mountHiddenHost()
    }

    // 本服务为 app 级常驻（启动创建、退出前不释放），故不实现 deinit 清理：
    // 隐藏 host 与两个 session 需要全程存活，进程退出时由系统统一回收。

    // MARK: - OfflineTranslating

    public func rewriteToEnglish(_ text: String) async throws -> String {
        try await enqueue(text, direction: .zhToEn)
    }

    public func lookupToChinese(_ text: String) async throws -> String {
        try await enqueue(text, direction: .enToZh)
    }

    public func availability() async -> OfflineAvailability {
        let pair = OfflineLanguagePair.chineseToEnglish
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: pair.sourceIdentifier),
            to: Locale.Language(identifier: pair.targetIdentifier)
        )
        switch status {
        case .installed: return .ready
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    // MARK: - Request plumbing (主 actor)

    private func enqueue(_ text: String, direction: Direction) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let item = WorkItem(id: UUID(), text: text)
            continuations[item.id] = continuation
            switch direction {
            case .zhToEn:
                pendingZhToEn.append(item)
                zhToEnSignalCont.yield(())
            case .enToZh:
                pendingEnToZh.append(item)
                enToZhSignalCont.yield(())
            }
        }
    }

    /// 取走并清空某方向的待处理批次（只返回 Sendable 的 WorkItem，不含 continuation）。
    fileprivate func takeWork(_ direction: Direction) -> [WorkItem] {
        switch direction {
        case .zhToEn:
            defer { pendingZhToEn.removeAll() }
            return pendingZhToEn
        case .enToZh:
            defer { pendingEnToZh.removeAll() }
            return pendingEnToZh
        }
    }

    /// 按 id 回传结果，在主 actor 上 resume 对应 continuation。
    fileprivate func fulfill(_ id: UUID, _ outcome: Outcome) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        switch outcome {
        case .success(let text): continuation.resume(returning: text)
        case .failure(let message): continuation.resume(throwing: OfflineTranslateError.failed(message))
        }
    }

    // MARK: - Hidden host

    private func mountHiddenHost() {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: OfflineHostView(service: self))
        window.orderFrontRegardless()
        self.window = window
    }
}

/// 隐藏 host 视图：常驻两个 `.translationTask`。每个闭包是无隔离域，session 留在域内
/// 调 `translate`（零跨界），只通过 Sendable 数据与主 actor 的 service 往返。
/// service 是 `@MainActor` 类（隐式 Sendable），用 `unowned` 引用破除保留环
/// （service 持有 window → contentView → 本视图，一定比视图活得久）。
@available(macOS 15, *)
private struct OfflineHostView: View {
    unowned let service: AppleTranslationService

    @State private var zhToEnConfig: TranslationSession.Configuration?
    @State private var enToZhConfig: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task {
                let zhToEn = OfflineLanguagePair.chineseToEnglish
                zhToEnConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: zhToEn.sourceIdentifier),
                    target: Locale.Language(identifier: zhToEn.targetIdentifier)
                )
                let enToZh = OfflineLanguagePair.englishToChinese
                enToZhConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: enToZh.sourceIdentifier),
                    target: Locale.Language(identifier: enToZh.targetIdentifier)
                )
            }
            .translationTask(zhToEnConfig) { session in
                for await _ in service.zhToEnSignal {
                    for item in service.takeWork(.zhToEn) {
                        let outcome: AppleTranslationService.Outcome
                        do {
                            outcome = .success(try await session.translate(item.text).targetText)
                        } catch {
                            outcome = .failure(error.localizedDescription)
                        }
                        service.fulfill(item.id, outcome)
                    }
                }
            }
            .translationTask(enToZhConfig) { session in
                for await _ in service.enToZhSignal {
                    for item in service.takeWork(.enToZh) {
                        let outcome: AppleTranslationService.Outcome
                        do {
                            outcome = .success(try await session.translate(item.text).targetText)
                        } catch {
                            outcome = .failure(error.localizedDescription)
                        }
                        service.fulfill(item.id, outcome)
                    }
                }
            }
    }
}

/// 一键下载离线语言包。点按后用 `.translationTask` + `prepareTranslation()` 触发 Apple
/// 原生下载弹窗——弹窗只列出所需的中文与英文，无需用户去系统设置层层翻找。
/// 必须挂在「可见窗口」里（设置窗口），系统弹窗才能正确依附。
@available(macOS 15, *)
struct OfflineLanguageDownloadButton: View {
    /// 下载结束（成功/取消/失败）后回调，供外部重新查询 availability 刷新状态。
    let onFinish: () async -> Void

    @State private var config: TranslationSession.Configuration?
    @State private var isPreparing = false

    var body: some View {
        Button {
            isPreparing = true
            let pair = OfflineLanguagePair.chineseToEnglish
            config = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.sourceIdentifier),
                target: Locale.Language(identifier: pair.targetIdentifier)
            )
        } label: {
            Label(isPreparing ? "下载中…" : "下载离线语言包（中 ⇄ 英）", systemImage: "arrow.down.circle")
        }
        .disabled(isPreparing)
        .translationTask(config) { session in
            // 触发系统原生下载弹窗（仅列出中文与英文）；用户取消/失败则静默
            try? await session.prepareTranslation()
            isPreparing = false
            config = nil
            await onFinish()
        }
    }
}
#endif
