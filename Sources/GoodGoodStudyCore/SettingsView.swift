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
