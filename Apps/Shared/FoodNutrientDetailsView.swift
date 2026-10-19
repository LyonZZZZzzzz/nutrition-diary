import SwiftUI
import NutritionKit

struct FoodNutrientDetailsView: View {
    @Environment(AppModel.self) private var model
    let food: FoodItem

    var body: some View {
        ForEach(NutrientGroup.allCases, id: \.self) { group in
            let definitions = NutrientCatalog.definitions(in: group)
            let available = definitions.filter { definition in
                food.nutrients.contains { $0.nutrient == definition.id && $0.value != nil }
            }
            if !available.isEmpty {
                DisclosureGroup(group.localizedTitle(for: model.effectiveLanguage)) {
                    ForEach(available) { definition in
                        let measurement = food.nutrients.first { $0.nutrient == definition.id }
                        NutrientRow(definition: definition, measurement: measurement)
                    }
                }
            }
        }
    }
}
