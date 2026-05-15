import SwiftUI

public struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?
    @State private var apiKey: String
    @State private var provider: AIProvider
    @State private var customBaseURL: String
    @State private var customModel: String
    @State private var translationStyle: TranslationStyle

    public init(store: SettingsStore, onClose: (() -> Void)? = nil) {
        self.store = store
        self.onClose = onClose
        _apiKey = State(initialValue: store.apiKey)
        _provider = State(initialValue: store.provider)
        _customBaseURL = State(initialValue: store.customBaseURL)
        _customModel = State(initialValue: store.customModel)
        _translationStyle = State(initialValue: store.translationStyle)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("瞎翻 Pro 设置")
                .font(.headline)

            // Provider picker
            VStack(alignment: .leading, spacing: 8) {
                Text("AI 服务商")
                    .font(.subheadline)
                Picker("", selection: $provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // API Key
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                SecureField("输入 API Key...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
            }

            // Custom provider fields
            if provider == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL")
                        .font(.subheadline)
                    TextField("https://api.example.com/v1", text: $customBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 400)
                    Text("Model Name")
                        .font(.subheadline)
                    TextField("model-name", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 400)
                }
            } else {
                Text("Endpoint: \(provider.defaultBaseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Model: \(provider.defaultModel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("翻译风格")
                    .font(.subheadline)
                ForEach(TranslationStyle.allCases) { style in
                    Button {
                        translationStyle = style
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: translationStyle == style ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(translationStyle == style ? Color.accentColor : Color.secondary)
                                .frame(width: 16, height: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(style.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    onClose?()
                    dismiss()
                }
                Button("保存") {
                    store.updateSettings(
                        apiKey: apiKey,
                        provider: provider,
                        customBaseURL: customBaseURL,
                        customModel: customModel,
                        translationStyle: translationStyle
                    )
                    onClose?()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
