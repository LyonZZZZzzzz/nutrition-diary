import SwiftUI
import NutritionKit

struct FoodDataSourceView: View {
    @Environment(AppModel.self) private var model
    private let manifest = CatalogManifest.bundled()

    var body: some View {
        List {
            if let manifest {
                Section("离线食物目录") {
                    LabeledContent("记录数", value: manifest.recordCount.formatted())
                    if let zh = manifest.nameZhCount, let en = manifest.nameEnCount {
                        LabeledContent(
                            model.localized("中文名称覆盖", "Chinese-name coverage"),
                            value: "\(zh.formatted()) / \(manifest.recordCount.formatted())"
                        )
                        .accessibilityIdentifier("foodData.chineseCoverage")
                        LabeledContent(
                            model.localized("英文名称覆盖", "English-name coverage"),
                            value: "\(en.formatted()) / \(manifest.recordCount.formatted())"
                        )
                    }
                    if let curated = manifest.nameZhCuratedCount,
                       let taiwan = manifest.nameZhTaiwanCount,
                       let machine = manifest.nameZhMachineCount {
                        LabeledContent(model.localized("人工审核名称", "Curated names"), value: curated.formatted())
                        LabeledContent(model.localized("台湾参考名称", "Taiwan reference names"), value: taiwan.formatted())
                        LabeledContent(model.localized("本地机器翻译", "Local machine translations"), value: machine.formatted())
                    }
                    LabeledContent("数据库大小", value: ByteCountFormatter.string(fromByteCount: Int64(manifest.database.bytes), countStyle: .file))
                    LabeledContent("生成时间", value: manifest.generatedAt)
                    LabeledContent("校验 SHA256", value: String(manifest.database.sha256.prefix(12)) + "…")
                }
                Section("数据来源与许可证") {
                    ForEach(manifest.sources, id: \.name) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.headline)
                            Text(model.localized("版本：\(source.version)", "Version: \(source.version)")).font(.caption).foregroundStyle(.secondary)
                            Text(model.localized("许可证：\(source.license)", "License: \(source.license)")).font(.caption).foregroundStyle(.secondary)
                            if let url = URL(string: source.url), !source.url.isEmpty {
                                Link("查看来源", destination: url).font(.caption)
                            }
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView("未读取到目录清单", systemImage: "externaldrive.badge.questionmark")
                }
            }
            Section("在线补充来源") {
                Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/")!)
                Text("包装食品在线数据使用 ODbL；需要保留归属，公开分发改编数据库时须遵守相同方式共享。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("说明") {
                Text("台湾 FDA 数据采用政府资料开放授权条款；USDA FoodData Central 数据为公共领域。App 只读使用打包目录，不上传查询内容。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("食物数据来源")
    }
}
