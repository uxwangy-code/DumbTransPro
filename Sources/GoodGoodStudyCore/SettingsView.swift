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

            // Provider picker
            VStack(alignment: .leading, spacing: 8) {
                Text("AI 服务商")
                    .font(.subheadline)
                Picker("", selection: $store.provider) {
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
                SecureField("输入 API Key...", text: $store.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
            }

            // Custom provider fields
            if store.provider == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL")
                        .font(.subheadline)
                    TextField("https://api.example.com/v1", text: $store.customBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 400)
                    Text("Model Name")
                        .font(.subheadline)
                    TextField("model-name", text: $store.customModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 400)
                }
            } else {
                // Show current endpoint info
                Text("Endpoint: \(store.baseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Model: \(store.model)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("取消") {
                    store.loadSettings()
                    dismiss()
                }
                Button("保存") {
                    store.saveSettings()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
