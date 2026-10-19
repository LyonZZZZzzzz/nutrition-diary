import SwiftUI
import NutritionKit

struct FoodsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var showCompositeEditor = false
    @State private var query = ""
    @State private var searchResults: [FoodSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索食物、别名", text: $query)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("食物目录") {
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在搜索…").foregroundStyle(.secondary)
                    }
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "未找到相关食物",
                        systemImage: "magnifyingglass",
                        description: Text("请检查名称或别名，或新建复合食物。")
                    )
                } else {
                    ForEach(searchResults) { result in
                        let food = result.food
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(food.localizedName(for: model.effectiveLanguage)).font(.headline)
                                    if !food.hasLocalizedName(for: model.effectiveLanguage), food.nameEn != nil {
                                        Text(model.localized("英文原名", "Source name"))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.14), in: Capsule())
                                    }
                                }
                                Text("\(food.localizedCategory(for: model.effectiveLanguage)) · \(food.source.localizedTitle(for: model.effectiveLanguage))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(model.localized("匹配：\(result.matchReason.localizedTitle(for: model.effectiveLanguage)) · \(result.matchedTerm)", "Match: \(result.matchReason.localizedTitle(for: model.effectiveLanguage)) · \(result.matchedTerm)"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .accessibilityIdentifier("foods.matchReason.\(food.id.uuidString.lowercased())")
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(food.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue ?? 0, specifier: "%.0f")")
                                    .font(.headline.monospacedDigit())
                                Text("kcal / 100\(food.referenceUnit.rawValue)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Text(model.localized("离线目录包含公开授权食物，并合并本地自定义和复合食物；搜索同时支持中英文名称与别名。", "The offline catalog combines licensed foods with local custom and composite foods. Search works across Chinese and English names and aliases."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("食物库")
        .toolbar {
            Menu {
                Button { showAdd = true } label: { Label("记录食物", systemImage: "fork.knife") }
                Button { showCompositeEditor = true } label: { Label("新建复合食物", systemImage: "square.stack.3d.up") }
            } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showAdd) { AddFoodSheet() }
        .sheet(isPresented: $showCompositeEditor) { CompositeFoodEditorView() }
        .task(id: query) { await performSearch() }
    }

    private func performSearch() async {
        let snapshot = query
        isSearching = true
        if !snapshot.isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
        }
        let results = await model.searchFoodResults(query: snapshot, limit: 50)
        guard !Task.isCancelled, snapshot == query else { return }
        searchResults = results
        isSearching = false
    }
}
