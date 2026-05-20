import AppKit
import SwiftUI

struct LookupPanelView: View {
    @ObservedObject var state: LookupPanelState

    private static let collapsedOriginalLineLimit = 2
    private static let originalHorizontalPadding: CGFloat = 14
    private static let originalTextFont = NSFont.systemFont(ofSize: 12)
    static let panelWidth: CGFloat = 480
    static let maxOriginalHeight: CGFloat = 200
    static let maxTranslationHeight: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            contentArea
        }
        .frame(width: Self.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .controlColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        )
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            originalTextSection
            insetDivider
            translationSection
            footerBar
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.96))
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .leading) {
                WindowDragHandle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text("划词翻译")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: 18)

            Button {
                state.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Color(nsColor: .tertiaryLabelColor).opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(nsColor: .controlColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(height: 1)
        }
    }

    private var insetDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.65))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private var originalTextSection: some View {
        let needsCollapse = originalTextNeedsCollapse
        return VStack(alignment: .leading, spacing: 4) {
            if needsCollapse && !state.isOriginalExpanded {
                Text(state.originalText)
                    .lineLimit(Self.collapsedOriginalLineLimit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("展开全文") {
                    state.isOriginalExpanded = true
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else {
                if needsCollapse {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(state.originalText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: Self.maxOriginalHeight)
                    Button("收起") {
                        state.isOriginalExpanded = false
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                } else {
                    Text(state.originalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Self.originalHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var originalTextNeedsCollapse: Bool {
        Self.textExceedsLineLimit(
            state.originalText,
            width: Self.panelWidth - Self.originalHorizontalPadding * 2,
            lineLimit: Self.collapsedOriginalLineLimit
        )
    }

    private static func textExceedsLineLimit(_ text: String, width: CGFloat, lineLimit: Int) -> Bool {
        let lineHeight = originalTextFont.ascender - originalTextFont.descender + originalTextFont.leading
        let maxCollapsedHeight = ceil(lineHeight * CGFloat(lineLimit))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let measuredRect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: originalTextFont,
                .paragraphStyle: paragraphStyle
            ]
        )

        return ceil(measuredRect.height) > maxCollapsedHeight + 1
    }

    @ViewBuilder
    private var translationSection: some View {
        if state.isLoading {
            HStack(alignment: .center, spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                Text(state.isSlowLoading
                     ? "文本较长,模型返回较慢。本工具不太适合翻译长文本,建议把原文拆短一点再试。"
                     : "翻译中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        } else if let error = state.error {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if state.didFallback {
                        Text("😅 太难了,我实在装不下去了...")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(state.translation)
                        .font(.title3)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .frame(maxHeight: Self.maxTranslationHeight)
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        if !state.modelName.isEmpty {
            HStack {
                Spacer()
                Text(state.modelName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

private final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
