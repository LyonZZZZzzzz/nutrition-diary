import Foundation
import Testing
@testable import NutritionKit

struct CompositeFoodTests {
    @Test
    func seedCatalogContainsRequestedFoods() throws {
        #expect(SeedCatalog.foods.count == 121)
        #expect(SeedCatalog.foods.contains { $0.name == "美式咖啡" })
        #expect(SeedCatalog.foods.contains { $0.name == "番茄" })
        #expect(SeedCatalog.foods.contains { $0.name == "猕猴桃" })
        let chocolate = try #require(SeedCatalog.foods.first { $0.name == "牛奶巧克力" })
        #expect(chocolate.portions.contains { $0.label == "1排" && $0.amount == 45 })
        #expect(chocolate.nutrients.first { $0.nutrient == NutrientCatalog.caffeine }?.doubleValue == 20)
    }

    @Test
    func recipeCompositeNormalizesToPer100Grams() throws {
        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let egg = try #require(SeedCatalog.foods.first { $0.name == "鸡蛋" })
        let composite = CompositeFoodDefinition(
            name: "蛋炒饭测试",
            mode: .recipe,
            ingredients: [
                RecipeIngredient(food: rice, quantity: .edibleGrams(150)),
                RecipeIngredient(food: egg, quantity: .edibleGrams(50))
            ],
            finalYieldGrams: 200
        )
        let food = try CompositeNutritionCalculator().foodItem(from: composite)
        let energy = try #require(food.nutrients.first { $0.nutrient == NutrientCatalog.energy })
        #expect(abs((energy.doubleValue ?? 0) - 133.25) < 0.001)
        #expect(energy.status == .complete)
    }

    @Test
    func missingYieldMarksCompositeEstimated() throws {
        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let composite = CompositeFoodDefinition(
            name: "无成品重量",
            mode: .recipe,
            ingredients: [RecipeIngredient(food: rice, quantity: .edibleGrams(100))]
        )
        let food = try CompositeNutritionCalculator().foodItem(from: composite)
        #expect(food.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.status == .estimated)
    }

    @Test
    func directCompositeUsesSuppliedValues() throws {
        let composite = CompositeFoodDefinition(
            name: "直接巧克力",
            mode: .direct,
            directNutrients: [
                .init(nutrient: NutrientCatalog.energy, value: 500, unit: .kilocalorie, status: .complete, source: .manual),
                .init(nutrient: NutrientCatalog.sugar, value: 50, unit: .gram, status: .complete, source: .manual)
            ]
        )
        let food = try CompositeNutritionCalculator().foodItem(from: composite)
        #expect(food.source.title == "直接营养数据")
        #expect(food.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue == 500)
    }
}
