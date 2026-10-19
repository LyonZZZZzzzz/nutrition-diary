import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import NutritionKit

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddFood = false
    @State private var showGoalEditor = false
    @State private var goalValue: Double = 0
    @State private var pendingDelete: DiaryEntry?
    @State private var targetedMeal: MealType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dateHeader
                calorieCards
                healthEnergyDetailCard
                if !(model.energyBalance?.isComplete ?? false) {
                    Label("Apple Watch 或健康数据不完整，热量平衡暂为部分结果", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 2)
                }
                nutritionCard
                mealsSection
            }
            .padding()
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("今日")
        .toolbar {
            ToolbarItemGroup {
                Button { showGoalEditor = true } label: { Label("平衡目标", systemImage: "scope") }
                Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Button { showAddFood = true } label: { Label("记录食物", systemImage: "plus") }
                    .accessibilityIdentifier("today.addFood")
            }
        }
        .sheet(isPresented: $showAddFood) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-add-food-search") {
                AddFoodSheet(initialQuery: "鸡")
            } else {
                AddFoodSheet()
            }
            #else
            AddFoodSheet()
            #endif
        }
        .sheet(isPresented: $showGoalEditor) { goalEditor }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-add-food-search") {
                showAddFood = true
            }
            #endif
        }
        .confirmationDialog(
            "删除饮食记录",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("仅删除记录") {
                Task { await model.delete(entry: entry); pendingDelete = nil }
            }
            if !entry.photoFilenames.isEmpty {
                Button("同时删除本地照片", role: .destructive) {
                    Task { await model.delete(entry: entry, deletePhotos: true); pendingDelete = nil }
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text(model.localized("\(entry.localizedFoodName(for: .simplifiedChinese)) 将从 \(entry.mealType.localizedTitle(for: .simplifiedChinese)) 中移除。", "\(entry.localizedFoodName(for: .english)) will be removed from \(entry.mealType.localizedTitle(for: .english))."))
        }
    }

    private var dateHeader: some View {
        HStack(spacing: 12) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedDate, format: .dateTime.month().day().weekday(.wide))
                    .font(.title2.bold())
                Text(model.dayKey).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("今天") { model.selectedDate = .now; Task { await model.load() } }
                .disabled(Calendar.current.isDateInToday(model.selectedDate))
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
    }

    private var calorieCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: model.localized("饮食摄入", "Dietary intake"), value: model.calorieText, unit: "kcal", tint: .orange,
                       note: model.hasMissingCoreNutrients ? model.localized("存在缺失营养", "Missing nutrients") : nil)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.intakeCard")
            MetricCard(title: model.localized("总消耗", "Total burn"), value: model.totalBurnText, unit: "kcal", tint: .blue,
                       note: sourceNote)
            MetricCard(title: model.localized("总热量平衡", "Total energy balance"), value: model.totalBalanceText, unit: "kcal", tint: .purple,
                       note: model.balanceGoal.map { model.localized("目标 \(String(format: "%+.0f", $0.targetBalanceKcal))", "Target \(String(format: "%+.0f", $0.targetBalanceKcal))") })
            MetricCard(title: model.localized("活动净平衡", "Active net balance"), value: model.activeBalanceText, unit: "kcal", tint: .teal)
        }
    }

    private var sourceNote: String? {
        guard let summary = model.energySummary else { return nil }
        let sourceIDs = [summary.activeSource, summary.basalSource].compactMap { $0 }
        let names = Set(sourceIDs.map { id in
            model.healthSources.first(where: { $0.id == id })?.localizedDisplayName(for: model.effectiveLanguage) ?? id
        }).sorted()
        let updated = summary.fetchedAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(model.effectiveLanguage.locale)
        )
        if sourceIDs.isEmpty { return model.localized("尚无健康消耗数据", "No health burn data") }
        return "\(names.joined(separator: " / ")) · \(updated)"
    }

    private var healthEnergyDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("健康消耗明细", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                if let fetchedAt = model.healthLastUpdatedAt {
                    Text(HealthUpdateTimeFormatter.text(from: fetchedAt, language: model.effectiveLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                healthValue(model.localized("活动能量", "Active energy"), model.energySummary?.activeKcal, "kcal", "figure.run")
                healthValue(model.localized("静息能量", "Resting energy"), model.energySummary?.basalKcal, "kcal", "bed.double.fill")
                healthValue(model.localized("锻炼时间", "Exercise time"), model.energySummary?.exerciseMinutes, model.localized("分钟", "min"), "timer")
                healthValue(model.localized("总消耗", "Total burn"), model.energySummary?.totalKcal, "kcal", "flame.fill")
            }
            if let note = model.energySummary?.coverageNote {
                Text(model.energySummary?.localizedCoverageNote(for: model.effectiveLanguage) ?? note).font(.caption).foregroundStyle(.secondary)
            }
            if model.healthSources.isEmpty {
                Text("尚未读取到健康来源。请在设置中授权或检查 Apple Watch 是否已同步到 Health。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func healthValue(_ title: String, _ value: Double?, _ unit: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value.map { "\(Int($0.rounded())) \(unit)" } ?? model.localized("缺失", "Missing"))
                    .font(.subheadline.bold().monospacedDigit())
            }
        }
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("营养成分").font(.headline)
                Spacer()
                Text(model.localized("\(model.entries.count) 条记录", "\(model.entries.count) entries")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(NutrientCatalog.definitions) { definition in
                NutrientRow(definition: definition, measurement: model.nutritionSummary?.totals[definition.id])
                if definition.id != NutrientCatalog.definitions.last?.id { Divider() }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日餐次").font(.headline)
                Spacer()
                Button { showAddFood = true } label: { Label("添加", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            if model.entries.isEmpty {
                ContentUnavailableView("还没有记录", systemImage: "fork.knife", description: Text("搜索食物或拍照开始记录。"))
                    .frame(minHeight: 180)
            } else {
                Text(model.localized("长按并拖动菜品到目标餐次。", "Press and drag a food item to another meal."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(MealType.allCases) { meal in
                    let mealEntries = model.entries.filter { $0.mealType == meal }
                    mealCard(meal: meal, entries: mealEntries, isDropTarget: targetedMeal == meal)
                        .dropDestination(for: DiaryEntryDragPayload.self) { payloads, _ in
                            handleDrop(payloads, to: meal)
                        } isTargeted: { isTargeted in
                            if isTargeted {
                                targetedMeal = meal
                            } else if targetedMeal == meal {
                                targetedMeal = nil
                            }
                        }
                }
            }
        }
    }

    private func mealCard(meal: MealType, entries: [DiaryEntry], isDropTarget: Bool) -> some View {
        let mealEnergy = entries.compactMap { entry in
            entry.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue
        }.reduce(0, +)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(meal.localizedTitle(for: model.effectiveLanguage), systemImage: mealIcon(meal))
                    .font(.headline)
                    .accessibilityIdentifier("today.meal.title.\(meal.rawValue)")
                Spacer()
                Text(entries.isEmpty ? "—" : "\(Int(mealEnergy.rounded())) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if entries.isEmpty {
                Label("拖动菜品到此餐次", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .accessibilityIdentifier("today.meal.dropHint.\(meal.rawValue)")
            } else {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
        }
        .padding()
        .background(
            isDropTarget ? Color.accentColor.opacity(0.12) : Color.platformMealCardBackground,
            in: shape
        )
        .overlay {
            shape.stroke(isDropTarget ? Color.accentColor : .clear, lineWidth: 2)
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.localizedFoodName(for: model.effectiveLanguage))
                Text(entry.localizedQuantityDescription(for: model.effectiveLanguage)).font(.caption).foregroundStyle(.secondary)
                if entry.source == .photoEstimate {
                    Label(model.localized("照片估算 · 置信度 \(Int((entry.photoConfidence ?? 0) * 100))%", "Photo estimate · \(Int((entry.photoConfidence ?? 0) * 100))% confidence"), systemImage: entry.photoFilenames.isEmpty ? "sparkles" : "photo")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text("\(entry.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue ?? 0, specifier: "%.0f") kcal")
                .font(.subheadline.monospacedDigit())
            Button(role: .destructive) {
                pendingDelete = entry
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.localized("删除", "Delete"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityIdentifier("today.entry.\(entry.id.uuidString.lowercased())")
        .accessibilityActions {
            ForEach(MealType.allCases.filter { $0 != entry.mealType }) { meal in
                Button(meal.localizedTitle(for: model.effectiveLanguage)) {
                    requestMove(entry, to: meal)
                }
            }
        }
        .draggable(DiaryEntryDragPayload(entryID: entry.id, dayKey: entry.dayKey)) {
            dragPreview(for: entry)
        }
    }

    private func handleDrop(_ payloads: [DiaryEntryDragPayload], to meal: MealType) -> Bool {
        targetedMeal = nil
        guard payloads.count == 1,
              let payload = payloads.first,
              payload.dayKey == model.dayKey,
              let entry = model.entries.first(where: { $0.id == payload.entryID }),
              entry.mealType != meal,
              !model.isMovingEntry(entry.id) else {
            return false
        }
        requestMove(entry, to: meal)
        return true
    }

    private func requestMove(_ entry: DiaryEntry, to meal: MealType) {
        Task {
            do {
                try await model.move(entry: entry, to: meal)
            } catch {
                model.errorMessage = localizedApplicationError(error, language: model.effectiveLanguage)
            }
        }
    }

    private func dragPreview(for entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.localizedFoodName(for: model.effectiveLanguage)).font(.headline)
            Text(entry.localizedQuantityDescription(for: model.effectiveLanguage)).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var goalEditor: some View {
        NavigationStack {
            Form {
                Section("每日热量平衡目标") {
                    Text("正值表示目标盈余，负值表示目标缺口。该值只用于计算目标摄入，不构成医疗建议。")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text("目标")
                        Slider(value: $goalValue, in: -1000...1000, step: 50)
                        Text("\(Int(goalValue)) kcal").monospacedDigit()
                    }
                }
            }
            .navigationTitle("平衡目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showGoalEditor = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await model.setBalanceGoal(goalValue); showGoalEditor = false }
                    }
                }
            }
            .onAppear { goalValue = model.balanceGoal?.targetBalanceKcal ?? 0 }
        }
    }

    private func shiftDay(_ offset: Int) {
        model.selectedDate = Calendar.current.date(byAdding: .day, value: offset, to: model.selectedDate) ?? model.selectedDate
        Task { await model.load() }
    }

    private func mealIcon(_ meal: MealType) -> String {
        switch meal {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }
}

private struct DiaryEntryDragPayload: Codable, Transferable, Sendable {
    let entryID: UUID
    let dayKey: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .nutritionDiaryEntry)
    }
}

private extension UTType {
    static let nutritionDiaryEntry = UTType(
        exportedAs: "com.lyonzhu.NutritionDiary.diary-entry",
        conformingTo: .data
    )
}

extension Color {
    static var platformGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var platformMealCardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
