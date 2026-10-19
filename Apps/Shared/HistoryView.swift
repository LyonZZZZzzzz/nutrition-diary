import SwiftUI
import NutritionKit

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("记录日期", selection: Binding(
                    get: { model.selectedDate },
                    set: { model.selectedDate = $0; Task { await model.load() } }
                ), displayedComponents: .date)
                .datePickerStyle(.compact)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MetricCard(title: model.localized("摄入", "Intake"), value: model.calorieText, unit: "kcal", tint: .orange)
                    MetricCard(title: model.localized("总消耗", "Total burn"), value: model.totalBurnText, unit: "kcal", tint: .blue, note: model.energySummary?.activeSource)
                    MetricCard(title: model.localized("总平衡", "Total balance"), value: model.totalBalanceText, unit: "kcal", tint: .purple)
                    MetricCard(title: model.localized("活动净平衡", "Active net balance"), value: model.activeBalanceText, unit: "kcal", tint: .teal)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("营养明细").font(.headline)
                    ForEach(NutrientCatalog.definitions) { definition in
                        NutrientRow(definition: definition, measurement: model.nutritionSummary?.totals[definition.id])
                        Divider()
                    }
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("当天记录").font(.headline)
                    if model.entries.isEmpty {
                        Text("没有记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.entries) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.localizedFoodName(for: model.effectiveLanguage))
                                    Text("\(entry.mealType.localizedTitle(for: model.effectiveLanguage)) · \(entry.localizedQuantityDescription(for: model.effectiveLanguage))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue ?? 0, specifier: "%.0f") kcal")
                                    .monospacedDigit()
                            }
                            Divider()
                        }
                    }
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("历史")
    }
}
