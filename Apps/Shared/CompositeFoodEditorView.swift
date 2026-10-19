import SwiftUI
import NutritionKit

struct CompositeFoodEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nameZh = ""
    @State private var nameEn = ""
    @State private var categoryZh = "复合食物"
    @State private var categoryEn = "Composite food"
    @State private var mode: CompositeNutritionMode = .recipe
    @State private var directUnit: FoodReferenceUnit = .gram
    @State private var directValues: [NutrientID: String] = [:]
    @State private var ingredients: [RecipeIngredient] = []
    @State private var finalYieldText = ""
    @State private var servingsText = "1"
    @State private var showIngredientPicker = false
    @State private var errorText: String?

    private let compositeCalculator = CompositeNutritionCalculator()

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("中文名称", text: $nameZh)
                    TextField("English name", text: $nameEn)
                    TextField("中文分类", text: $categoryZh)
                    TextField("English category", text: $categoryEn)
                    Picker("计算方式", selection: $mode) {
                        ForEach(CompositeNutritionMode.allCases, id: \.self) { mode in
                            Text(mode.localizedTitle(for: model.effectiveLanguage)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .recipe {
                    recipeSections
                } else {
                    directSections
                }

                previewSection

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("新建复合食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(localizedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showIngredientPicker) {
                IngredientPickerView { food in
                    ingredients.append(RecipeIngredient(food: food, quantity: .edibleGrams(100)))
                }
            }
        }
    }

    private var recipeSections: some View {
        Group {
            Section("食材") {
                ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ingredient.food.localizedName(for: model.effectiveLanguage))
                            Text("\(ingredient.food.localizedCategory(for: model.effectiveLanguage)) · \(ingredient.food.source.localizedTitle(for: model.effectiveLanguage))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("100", text: ingredientAmountBinding(index: index))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("克").foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in ingredients.remove(atOffsets: offsets) }
                Button("添加食材") { showIngredientPicker = true }
            }
            Section("成品") {
                HStack {
                    Text("成品总重量")
                    TextField("留空则使用食材总重量", text: $finalYieldText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("克").foregroundStyle(.secondary)
                }
                HStack {
                    Text("份数")
                    TextField("1", text: $servingsText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("份").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var directSections: some View {
        Section("每 100 单位直接营养") {
            Picker("基准单位", selection: $directUnit) {
                Text("克").tag(FoodReferenceUnit.gram)
                Text("毫升").tag(FoodReferenceUnit.milliliter)
            }
            ForEach(NutrientCatalog.coreDefinitions) { definition in
                HStack {
                    Text(definition.localizedName(for: model.effectiveLanguage))
                    Spacer()
                    TextField("缺失", text: directBinding(definition.id))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                    Text(definition.unit.symbol).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = previewFood {
            Section("预览") {
                LabeledContent("来源", value: preview.source.localizedTitle(for: model.effectiveLanguage))
                ForEach(NutrientCatalog.coreDefinitions) { definition in
                    let measurement = preview.nutrients.first { $0.nutrient == definition.id }
                    NutrientRow(definition: definition, measurement: measurement)
                }
            }
        }
    }

    private func ingredientAmountBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard ingredients.indices.contains(index) else { return "" }
                switch ingredients[index].quantity {
                case .edibleGrams(let grams): return "\(grams)"
                case .purchasedGrams(let grams): return "\(grams)"
                case .milliliters(let milliliters): return "\(milliliters)"
                case .portion(_, let count): return "\(count)"
                }
            },
            set: { value in
                guard ingredients.indices.contains(index), let grams = Decimal(string: value), grams > 0 else { return }
                let food = ingredients[index].food
                ingredients[index] = RecipeIngredient(food: food, quantity: .edibleGrams(grams))
            }
        )
    }

    private func directBinding(_ nutrient: NutrientID) -> Binding<String> {
        Binding(get: { directValues[nutrient] ?? "" }, set: { directValues[nutrient] = $0 })
    }

    private var localizedName: String {
        model.effectiveLanguage.isChinese
            ? (nameZh.isEmpty ? nameEn : nameZh)
            : (nameEn.isEmpty ? nameZh : nameEn)
    }

    private var localizedCategory: String {
        model.effectiveLanguage.isChinese
            ? (categoryZh.isEmpty ? categoryEn : categoryZh)
            : (categoryEn.isEmpty ? categoryZh : categoryEn)
    }

    private var draft: CompositeFoodDefinition {
        let nutrients = NutrientCatalog.coreDefinitions.compactMap { definition -> NutrientMeasurement? in
            guard let raw = directValues[definition.id], let value = Decimal(string: raw), value >= 0 else { return nil }
            return NutrientMeasurement(nutrient: definition.id, value: value, unit: definition.unit, status: .estimated, source: .manual)
        }
        let servings = Decimal(string: servingsText) ?? 1
        return CompositeFoodDefinition(
            name: localizedName,
            nameZh: nameZh.isEmpty ? nameEn : nameZh,
            nameEn: nameEn.isEmpty ? nameZh : nameEn,
            category: localizedCategory,
            categoryZh: categoryZh.isEmpty ? categoryEn : categoryZh,
            categoryEn: categoryEn.isEmpty ? categoryZh : categoryEn,
            mode: mode,
            directReferenceUnit: directUnit,
            directNutrients: nutrients,
            ingredients: ingredients,
            finalYieldGrams: Decimal(string: finalYieldText),
            servings: servings,
            updatedAt: .now
        )
    }

    private var previewFood: FoodItem? {
        try? compositeCalculator.foodItem(from: draft)
    }

    private func save() {
        do {
            _ = try compositeCalculator.foodItem(from: draft)
            let definition = draft
            Task {
                do {
                    try await model.saveComposite(definition)
                    dismiss()
                } catch {
                    errorText = localizedApplicationError(error, language: model.effectiveLanguage)
                }
            }
        } catch {
            errorText = localizedApplicationError(error, language: model.effectiveLanguage)
        }
    }
}

private struct IngredientPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onSelect: (FoodItem) -> Void
    @State private var query = ""
    @State private var results: [FoodItem] = []

    var body: some View {
        NavigationStack {
            List {
                TextField("搜索食材", text: $query)
                    .onChange(of: query) { _, value in
                        Task { results = await model.catalog.search(query: value, limit: 40, language: model.effectiveLanguage) }
                    }
                ForEach(results) { food in
                    Button {
                        onSelect(food)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(food.localizedName(for: model.effectiveLanguage))
                            Text("\(food.localizedCategory(for: model.effectiveLanguage)) · \(food.source.localizedTitle(for: model.effectiveLanguage))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("添加食材")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { results = await model.catalog.search(query: "", limit: 40, language: model.effectiveLanguage) }
        }
    }
}
