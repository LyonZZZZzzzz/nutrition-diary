import SwiftUI
import NutritionKit

private enum FoodQuantityMode: String, CaseIterable, Identifiable {
    case measured
    case portion

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.measured, .simplifiedChinese): "克数 / 毫升"
        case (.portion, .simplifiedChinese): "家庭份量"
        case (.measured, .english): "Weight / Volume"
        case (.portion, .english): "Household portion"
        }
    }
}

struct AddFoodSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var searchResults: [FoodSearchResult] = []
    @State private var isSearching = false
    @State private var selectedFood: FoodItem?
    @State private var measuredAmountText = "100"
    @State private var quantityMode: FoodQuantityMode = .measured
    @State private var selectedPortionID: UUID?
    @State private var portionCountText = "1"
    @State private var mealType: MealType = .lunch
    @State private var isSaving = false

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let food = selectedFood {
                    quantityForm(food: food)
                } else {
                    searchList
                }
            }
            .navigationTitle(selectedFood == nil ? model.localized("搜索食物", "Search foods") : model.localized("确认份量", "Confirm portion"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedFood == nil ? model.localized("取消", "Cancel") : model.localized("返回", "Back")) {
                        if selectedFood == nil { dismiss() } else { selectedFood = nil }
                    }
                }
                if let food = selectedFood {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            save(food: food)
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("记录")
                            }
                        }
                        .disabled(quantity(for: food) == nil || isSaving)
                        .accessibilityIdentifier("addFood.save")
                    }
                }
            }
        }
        .onAppear { mealType = model.selectedMeal }
        .task(id: query) { await performSearch() }
    }

    private var searchList: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索食物、别名或菜品", text: $query)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .accessibilityIdentifier("addFood.searchField")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("addFood.clearSearch")
                    }
                }
            }
            Section("食物库") {
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在搜索…").foregroundStyle(.secondary)
                    }
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "未找到相关食物",
                        systemImage: "magnifyingglass",
                        description: Text("请检查名称或别名，也可以新建复合食物。")
                    )
                    .accessibilityIdentifier("addFood.noResults")
                } else {
                    ForEach(searchResults) { result in
                        let food = result.food
                        Button {
                            select(food)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(food.localizedName(for: model.effectiveLanguage))
                                    Text(food.aliases.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(model.localized("匹配：\(result.matchReason.localizedTitle(for: model.effectiveLanguage)) · \(result.matchedTerm)", "Match: \(result.matchReason.localizedTitle(for: model.effectiveLanguage)) · \(result.matchedTerm)"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .accessibilityIdentifier("addFood.matchReason.\(food.id.uuidString.lowercased())")
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(energyText(for: food))
                                        .font(.caption.monospacedDigit())
                                    Text("kcal / 100\(food.referenceUnit.localizedTitle(for: model.effectiveLanguage))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("addFood.result.\(food.id.uuidString.lowercased())")
                    }
                }
            }
            Section("说明") {
                Text(model.localized("离线目录包含公开授权食物，并合并本地自定义和复合食物；搜索同时支持中英文名称与别名。", "The offline catalog combines licensed foods with local custom and composite foods. Search works across Chinese and English names and aliases."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func quantityForm(food: FoodItem) -> some View {
        Form {
            Section("食物") {
                LabeledContent("名称", value: food.localizedName(for: model.effectiveLanguage))
                LabeledContent("基准", value: model.localized("每 100 \(food.referenceUnit.localizedTitle(for: model.effectiveLanguage))", "Per 100 \(food.referenceUnit.localizedTitle(for: model.effectiveLanguage))"))
                LabeledContent("来源", value: food.source.localizedTitle(for: model.effectiveLanguage))
                LabeledContent("可食比例", value: "\(food.edibleRatio)")
                if food.nameZhOrigin == .localMachineTranslation {
                    LabeledContent("中文名称来源", value: model.localized("本地机器翻译", "Local machine translation"))
                    LabeledContent("英文原名", value: food.nameEn ?? food.name)
                    Text("中文名称为本地机器翻译，建议对照英文原名核对。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("addFood.machineTranslationNote")
                }
            }

            if !food.portions.isEmpty {
                Section("录入方式") {
                    Picker("录入方式", selection: $quantityMode) {
                        ForEach(FoodQuantityMode.allCases) { mode in
                            Text(mode.title(for: model.effectiveLanguage))
                                .tag(mode)
                                .accessibilityIdentifier("addFood.quantityMode.\(mode.rawValue)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("addFood.quantityMode")
                }
            }

            if quantityMode == .portion, !food.portions.isEmpty {
                Section("家庭份量") {
                    Picker("份量", selection: Binding(
                        get: { selectedPortionID ?? food.portions.first?.id },
                        set: { selectedPortionID = $0 }
                    )) {
                        ForEach(food.portions) { portion in
                            Text(portion.localizedLabel(for: model.effectiveLanguage)).tag(Optional(portion.id))
                        }
                    }
                    .accessibilityIdentifier("addFood.portionPicker")

                    HStack {
                        Text("份数")
                        TextField("1", text: $portionCountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("addFood.portionCount")
                    }

                    if let equivalent = portionEquivalentText(food: food) {
                        LabeledContent("约等于", value: equivalent)
                            .accessibilityIdentifier("addFood.portionEquivalent")
                    }
                }
            } else {
                Section("份量") {
                    HStack {
                        Text(food.referenceUnit == .gram ? "克数" : "毫升")
                        TextField(food.referenceUnit == .gram ? "100" : "100", text: $measuredAmountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("addFood.measuredAmount")
                    }
                }
            }

            Section("餐次") {
                Picker("餐次", selection: $mealType) {
                    ForEach(MealType.allCases) { meal in
                        Text(meal.localizedTitle(for: model.effectiveLanguage)).tag(meal)
                    }
                }
            }

            previewSection(food: food)

            if quantity(for: food) == nil {
                Section {
                    Text(model.localized("请输入有效的份量", "Enter a valid portion"))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("addFood.invalidQuantity")
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(food: FoodItem) -> some View {
        Section("营养预览") {
            if let preview = nutritionPreview(food: food) {
                ForEach(NutrientCatalog.coreDefinitions) { definition in
                    let measurement = preview.nutrients.first { $0.nutrient == definition.id }
                    HStack {
                        Text(definition.localizedName(for: model.effectiveLanguage))
                        Spacer()
                        if let value = measurement?.doubleValue {
                            Text("\(value, specifier: "%.\(definition.displayDigits)f") \(definition.unit.symbol)")
                                .monospacedDigit()
                                .accessibilityIdentifier("addFood.preview.\(definition.id.rawValue)")
                        } else {
                            Text("缺失")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("addFood.preview.\(definition.id.rawValue)")
                        }
                        statusBadge(measurement?.status)
                    }
                }
            } else {
                Text("请输入有效份量后查看营养")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: NutrientStatus?) -> some View {
        switch status {
        case .estimated:
            Text("估算")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: Capsule())
        case .missing, .none:
            Text("不完整")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.12), in: Capsule())
        case .complete:
            EmptyView()
        }
    }

    private func select(_ food: FoodItem) {
        selectedFood = food
        measuredAmountText = "\(food.referenceAmount)"
        selectedPortionID = food.portions.first?.id
        portionCountText = "1"
        quantityMode = .measured
    }

    private func quantity(for food: FoodItem) -> FoodQuantity? {
        switch quantityMode {
        case .measured:
            guard let amount = Decimal(string: measuredAmountText), amount > 0 else { return nil }
            return food.referenceUnit == .gram ? .edibleGrams(amount) : .milliliters(amount)
        case .portion:
            guard let portionID = selectedPortionID ?? food.portions.first?.id,
                  let count = Decimal(string: portionCountText), count > 0 else { return nil }
            return .portion(id: portionID, count: count)
        }
    }

    private func nutritionPreview(food: FoodItem) -> NutritionComputation? {
        guard let quantity = quantity(for: food) else { return nil }
        return try? model.previewNutrition(food: food, quantity: quantity)
    }

    private func energyText(for food: FoodItem) -> String {
        guard let energy = food.nutrients.first(where: { $0.nutrient == NutrientCatalog.energy })?.doubleValue else {
            return "—"
        }
        return String(format: "%.0f", energy)
    }

    private func portionEquivalentText(food: FoodItem) -> String? {
        guard let portionID = selectedPortionID ?? food.portions.first?.id,
              let portion = food.portion(id: portionID),
              let count = Decimal(string: portionCountText), count > 0 else { return nil }
        let amount = portion.amount * count
        return "\(amount) \(portion.unit.localizedTitle(for: model.effectiveLanguage))"
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

    private func save(food: FoodItem) {
        guard let quantity = quantity(for: food), !isSaving else { return }
        isSaving = true
        Task {
            do {
                _ = try await model.add(food: food, quantity: quantity, mealType: mealType)
                dismiss()
            } catch {
                model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage)
                isSaving = false
            }
        }
    }
}
