import SwiftUI

struct LookupPanelView: View {
    @ObservedObject var state: LookupPanelState

    private let collapseThreshold = 100
    static let panelWidth: CGFloat = 480
    static let maxOriginalHeight: CGFloat = 200
    static let maxTranslationHeight: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            originalTextSection
            Divider()
            translationSection
            footerBar
        }
        .frame(width: Self.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            Text("划词翻译")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
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
    }

    private var originalTextSection: some View {
        let needsCollapse = state.originalText.count > collapseThreshold
        return VStack(alignment: .leading, spacing: 4) {
            if needsCollapse && !state.isOriginalExpanded {
                Text(state.originalText)
                    .lineLimit(2)
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
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
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
