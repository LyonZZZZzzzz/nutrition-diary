import SwiftUI

struct DeepSeekKeyEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek API Key") {
                    SecureField("sk-...", text: $apiKey)
                        .textContentType(.password)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    LabeledContent("状态", value: model.deepSeekStatusText)
                    Text("Key 只保存在本机 Keychain，不进入 iCloud Keychain、日志、备份或版本归档。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Button("保存并测试") {
                        isWorking = true
                        Task {
                            await model.saveDeepSeekAPIKey(apiKey)
                            isWorking = false
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                    Button("仅测试当前 Key") {
                        isWorking = true
                        Task {
                            await model.testDeepSeekAPIKey(apiKey.isEmpty ? nil : apiKey)
                            isWorking = false
                        }
                    }
                    .disabled(isWorking)

                    if model.deepSeekConfigured {
                        Button("删除已保存 Key", role: .destructive) {
                            model.deleteDeepSeekAPIKey()
                            apiKey = ""
                        }
                    }
                }

                Section(model.localized("识别说明", "Recognition details")) {
                    Text("混合餐识别只提取菜品、食材和份量，营养由本地目录计算。包装标签识别会提取可见营养数值，并保持“估算”状态等待确认。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("每次分析前仍会单独确认照片上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DeepSeek 识别")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if let saved = DeepSeekCredentialStore().load() {
                    apiKey = saved
                }
            }
        }
    }
}
