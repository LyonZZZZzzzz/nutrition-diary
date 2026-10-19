import Foundation
import Testing
@testable import NutritionKit

struct FoodRecordingFlowTests {
    @Test
    func bundledCatalogFindsChineseAliasesAndEnglishFoodNames() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())

        let eggResults = await catalog.searchResults(query: "鸡蛋", limit: 20, language: .simplifiedChinese)
        #expect(eggResults.first?.food.nameZh == "鸡蛋")

        let sweetPotato = await catalog.searchResults(query: "地瓜", limit: 20, language: .simplifiedChinese)
        #expect(sweetPotato.first?.food.nameZh == "红薯")

        let latte = await catalog.searchResults(query: "拿铁", limit: 20, language: .simplifiedChinese)
        #expect(latte.contains { $0.food.nameZh == "拿铁咖啡" })

        let apple = await catalog.searchResults(query: "apple", limit: 20, language: .english)
        #expect(apple.contains { $0.food.nameEn == "Apple" })
    }

    @Test
    func measuredAndHouseholdPortionsProduceExpectedEnergyAndMacros() throws {
        let calculator = NutritionCalculator()

        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let riceByWeight = try calculator.compute(food: rice, quantity: .edibleGrams(100))
        #expect(riceByWeight.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue == 130)
        #expect(riceByWeight.nutrients.first { $0.nutrient == NutrientCatalog.protein }?.doubleValue == 2.7)
        #expect(riceByWeight.nutrients.first { $0.nutrient == NutrientCatalog.carbohydrates }?.doubleValue == 28.2)

        let egg = try #require(SeedCatalog.foods.first { $0.name == "鸡蛋" })
        let eggPortion = try #require(egg.portions.first)
        let oneEgg = try calculator.compute(food: egg, quantity: .portion(id: eggPortion.id, count: 1))
        #expect(oneEgg.normalizedAmount == 50)
        #expect(oneEgg.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue == 71.5)
        #expect(oneEgg.nutrients.first { $0.nutrient == NutrientCatalog.protein }?.doubleValue == 6.3)

        let riceBowl = try #require(rice.portions.first)
        let oneBowl = try calculator.compute(food: rice, quantity: .portion(id: riceBowl.id, count: 1))
        #expect(oneBowl.normalizedAmount == 150)
        #expect(oneBowl.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue == 195)
    }

    @Test
    func savedEntriesPersistAndSummarizeFullNutritionRegistry() async throws {
        let calculator = NutritionCalculator()
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        let dayKey = "2026-10-17"
        let occurredAt = Date(timeIntervalSince1970: 1_800_000_000)

        let egg = try #require(SeedCatalog.foods.first { $0.name == "鸡蛋" })
        let eggPortion = try #require(egg.portions.first)
        let eggQuantity = FoodQuantity.portion(id: eggPortion.id, count: 1)
        let eggNutrition = try calculator.compute(food: egg, quantity: eggQuantity)
        let eggEntry = DiaryEntry(
            dayKey: dayKey,
            occurredAt: occurredAt,
            mealType: .breakfast,
            foodID: egg.id,
            foodName: egg.name,
            foodNameZh: egg.nameZh,
            foodNameEn: egg.nameEn,
            quantityDescription: "1 × 1个",
            quantityDescriptionZh: "1 × 1个",
            quantityDescriptionEn: "1 × 1 piece",
            normalizedAmount: eggNutrition.normalizedAmount,
            normalizedUnit: eggNutrition.normalizedUnit,
            nutrients: eggNutrition.nutrients,
            source: .bundledCatalog
        )
        try await store.save(eggEntry)

        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let ricePortion = try #require(rice.portions.first)
        let riceQuantity = FoodQuantity.portion(id: ricePortion.id, count: 1)
        let riceNutrition = try calculator.compute(food: rice, quantity: riceQuantity)
        let riceEntry = DiaryEntry(
            dayKey: dayKey,
            occurredAt: occurredAt.addingTimeInterval(60),
            mealType: .lunch,
            foodID: rice.id,
            foodName: rice.name,
            foodNameZh: rice.nameZh,
            foodNameEn: rice.nameEn,
            quantityDescription: "1 × 1碗",
            quantityDescriptionZh: "1 × 1碗",
            quantityDescriptionEn: "1 × 1 bowl",
            normalizedAmount: riceNutrition.normalizedAmount,
            normalizedUnit: riceNutrition.normalizedUnit,
            nutrients: riceNutrition.nutrients,
            source: .bundledCatalog
        )
        try await store.save(riceEntry)

        let entries = try await store.entries(dayKey: dayKey)
        #expect(entries.count == 2)
        #expect(entries.first?.localizedFoodName(for: .simplifiedChinese) == "鸡蛋")
        #expect(entries.first?.nutrients.first { $0.nutrient == NutrientCatalog.energy }?.doubleValue == 71.5)

        let summary = calculator.summarize(
            entries: entries,
            expectedNutrients: NutrientCatalog.definitions.map(\.id)
        )
        #expect(summary.entryCount == 2)
        #expect(summary.totals.energyKcal == 266.5)
        #expect(summary.totals[NutrientCatalog.protein]?.doubleValue == 10.35)
        #expect(summary.totals[NutrientCatalog.energy]?.status == .estimated)
        #expect(summary.totals[NutrientCatalog.vitaminA]?.status == .missing)
    }
}

extension FoodRecordingFlowTests {
    @Test
    func movedEntryPreservesIdentityNutritionAndPhotoReferences() {
        let sessionID = UUID()
        let entryID = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let originalTime = Date(timeIntervalSince1970: 200)
        let targetTime = Date(timeIntervalSince1970: 300)
        let updatedAt = Date(timeIntervalSince1970: 400)
        let nutrient = NutrientMeasurement(
            nutrient: NutrientCatalog.energy,
            value: 240,
            unit: .kilocalorie,
            status: .estimated,
            source: .photoEstimate
        )
        let original = DiaryEntry(
            id: entryID,
            sessionID: sessionID,
            dayKey: "2026-10-17",
            occurredAt: originalTime,
            timeZoneIdentifier: "Asia/Shanghai",
            mealType: .breakfast,
            foodID: UUID(),
            foodName: "Photo meal",
            foodNameZh: "照片餐食",
            foodNameEn: "Photo meal",
            quantityDescription: "约 200 克（照片估算）",
            quantityDescriptionZh: "约 200 克（照片估算）",
            quantityDescriptionEn: "About 200 g (photo estimate)",
            normalizedAmount: 200,
            normalizedUnit: .gram,
            nutrients: [nutrient],
            source: .photoEstimate,
            photoConfidence: 0.82,
            photoFilenames: ["meal-photo.heic"],
            createdAt: createdAt
        )

        let moved = original.moved(to: .dinner, occurredAt: targetTime, updatedAt: updatedAt)

        #expect(moved.id == entryID)
        #expect(moved.sessionID == sessionID)
        #expect(moved.dayKey == "2026-10-17")
        #expect(moved.timeZoneIdentifier == "Asia/Shanghai")
        #expect(moved.mealType == .dinner)
        #expect(moved.occurredAt == targetTime)
        #expect(moved.updatedAt == updatedAt)
        #expect(moved.createdAt == createdAt)
        #expect(moved.nutrients == [nutrient])
        #expect(moved.photoFilenames == ["meal-photo.heic"])
        #expect(moved.photoConfidence == 0.82)
        #expect(moved.foodNameZh == "照片餐食")
        #expect(moved.foodNameEn == "Photo meal")
    }

    @Test
    func movedEntryUpdatesExistingRecordWithoutDuplicatingIt() async throws {
        let container = try NutritionStoreFactory.makeContainer(inMemory: true)
        let store = DiaryStore(modelContainer: container)
        let calculator = NutritionCalculator()
        let egg = try #require(SeedCatalog.foods.first { $0.name == "鸡蛋" })
        let portion = try #require(egg.portions.first)
        let nutrition = try calculator.compute(food: egg, quantity: .portion(id: portion.id, count: 1))
        let original = DiaryEntry(
            dayKey: "2026-10-17",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            mealType: .breakfast,
            foodID: egg.id,
            foodName: egg.name,
            foodNameZh: egg.nameZh,
            foodNameEn: egg.nameEn,
            quantityDescription: "1 × 1个",
            quantityDescriptionZh: "1 × 1个",
            quantityDescriptionEn: "1 × 1 piece",
            normalizedAmount: nutrition.normalizedAmount,
            normalizedUnit: nutrition.normalizedUnit,
            nutrients: nutrition.nutrients,
            source: .bundledCatalog
        )
        try await store.save(original)

        let moved = original.moved(
            to: .dinner,
            occurredAt: Date(timeIntervalSince1970: 1_800_036_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_100_000)
        )
        try await store.save(moved)

        let entries = try await store.entries(dayKey: original.dayKey)
        #expect(entries.count == 1)
        #expect(entries.first?.id == original.id)
        #expect(entries.first?.mealType == .dinner)
        #expect(entries.first?.occurredAt == moved.occurredAt)
        let summary = calculator.summarize(
            entries: entries,
            expectedNutrients: NutrientCatalog.definitions.map(\.id)
        )
        #expect(summary.entryCount == 1)
        #expect(summary.totals.energyKcal == 71.5)
    }
}
