import SwiftUI
import NutritionKit

struct CatalogImportPreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let preview: CatalogImportPreview
    @State private var errorText: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("导入摘要") {
                    LabeledContent("可导入食物", value: "\(preview.foods.count)")
                    if !preview.unknownColumns.isEmpty {
                        Text(model.localized("未知列：\(preview.unknownColumns.joined(separator: "、"))", "Unknown columns: \(preview.unknownColumns.joined(separator: ", "))"))
                            .foregroundStyle(.orange)
                    }
                    if !preview.duplicateNames.isEmpty {
                        Text(model.localized("重复名称：\(preview.duplicateNames.joined(separator: "、"))", "Duplicate names: \(preview.duplicateNames.joined(separator: ", "))"))
                            .foregroundStyle(.red)
                    }
                }
                if !preview.issues.isEmpty {
                    Section("错误") {
                        ForEach(Array(preview.issues.enumerated()), id: \.offset) { _, issue in
                            Text(model.localized("第 \(issue.row) 行：\(issue.message)", "Row \(issue.row): \(localizedIssue(issue.message))"))
                                .font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                Section("预览") {
                    ForEach(preview.foods.prefix(20)) { food in
                        VStack(alignment: .leading) {
                            Text(food.localizedName(for: model.effectiveLanguage))
                            Text("\(food.localizedCategory(for: model.effectiveLanguage)) · \(food.source.localizedTitle(for: model.effectiveLanguage))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("CSV 导入预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? model.localized("导入中…", "Importing…") : model.localized("导入", "Import")) {
                        isImporting = true
                        Task {
                            do {
                                try await model.importFoods(preview.foods)
                                dismiss()
                            } catch {
                                errorText = localizedApplicationError(error, language: model.effectiveLanguage)
                                isImporting = false
                            }
                        }
                    }
                    .disabled(!preview.canCommit || isImporting)
                }
            }
        }
    }

    private func localizedIssue(_ message: String) -> String {
        guard !model.effectiveLanguage.isChinese else { return message }
        if message == "缺少 name" { return "Missing name" }
        if message == "referenceAmount 必须大于零" { return "referenceAmount must be greater than zero" }
        if message == "referenceUnit 只能是 g 或 ml" { return "referenceUnit must be g or ml" }
        if message.hasSuffix(" 不是有效非负数") {
            return message.replacingOccurrences(of: " 不是有效非负数", with: " must be a valid non-negative number")
        }
        if message.hasPrefix("与第 "), let range = message.range(of: " 行名称重复：") {
            let row = message[message.index(message.startIndex, offsetBy: 3)..<range.lowerBound]
            let name = message[range.upperBound...]
            return "Duplicate name from row \(row): \(name)"
        }
        return message
    }
}
