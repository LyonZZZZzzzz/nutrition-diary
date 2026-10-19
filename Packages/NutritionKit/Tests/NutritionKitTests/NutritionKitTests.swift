import Foundation
import Testing
@testable import NutritionKit

struct NutritionKitTests {
    private let calculator = NutritionCalculator()

    @Test
    func scalesFoodByEdibleGrams() throws {
        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let result = try calculator.compute(food: rice, quantity: .edibleGrams(150))
        let energy = try #require(result.nutrients.first { $0.nutrient == NutrientCatalog.energy })
        #expect(result.normalizedAmount == 150)
        #expect(energy.doubleValue == 195)
        #expect(energy.status == .complete)
    }

    @Test
    func purchasedWeightUsesEdibleRatio() throws {
        var food = try #require(SeedCatalog.foods.first { $0.name == "香蕉" })
        food.edibleRatio = Decimal(string: "0.67")!
        let result = try calculator.compute(food: food, quantity: .purchasedGrams(150))
        #expect(result.normalizedAmount == Decimal(string: "100.5"))
        #expect(result.warnings.isEmpty)
    }

    @Test
    func volumeFoodUsesMilliliterReference() throws {
        let milk = try #require(SeedCatalog.foods.first { $0.name == "全脂牛奶" })
        let result = try calculator.compute(food: milk, quantity: .milliliters(240))
        let energy = try #require(result.nutrients.first { $0.nutrient == NutrientCatalog.energy })
        #expect(result.normalizedAmount == 240)
        #expect(abs((energy.doubleValue ?? 0) - 146.4) < 0.001)
    }

    @Test
    func portionMarksNutritionEstimated() throws {
        let egg = try #require(SeedCatalog.foods.first { $0.name == "鸡蛋" })
        let portion = try #require(egg.portions.first)
        let result = try calculator.compute(food: egg, quantity: .portion(id: portion.id, count: 2))
        let energy = try #require(result.nutrients.first { $0.nutrient == NutrientCatalog.energy })
        #expect(result.normalizedAmount == 100)
        #expect(energy.status == .estimated)
    }

    @Test
    func recipeSumsIngredients() throws {
        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let egg = try #require(SeedCatalog.foods.first { $0.name == "鸡蛋" })
        let recipe = Recipe(
            name: "蛋炒饭",
            ingredients: [
                RecipeIngredient(food: rice, quantity: .edibleGrams(150)),
                RecipeIngredient(food: egg, quantity: .edibleGrams(50))
            ]
        )
        let nutrients = try calculator.compute(recipe: recipe)
        let energy = try #require(nutrients.first { $0.nutrient == NutrientCatalog.energy })
        #expect(energy.doubleValue == 266.5)
    }

    @Test
    func summaryDoesNotTurnMissingIntoTotals() throws {
        let rice = try #require(SeedCatalog.foods.first { $0.name == "白米饭" })
        let computed = try calculator.compute(food: rice, quantity: .edibleGrams(100))
        let entry = DiaryEntry(
            dayKey: "2026-10-17",
            occurredAt: .now,
            mealType: .lunch,
            foodID: rice.id,
            foodName: rice.name,
            quantityDescription: "100 克",
            normalizedAmount: 100,
            normalizedUnit: .gram,
            nutrients: [NutrientMeasurement.missing(NutrientCatalog.energy, unit: .kilocalorie, source: .manual)],
            source: .manual
        )
        let summary = calculator.summarize(entries: [entry])
        #expect(summary.hasMissingValues)
        #expect(summary.totals.energyKcal == nil)
        #expect(computed.nutrients.count == NutrientCatalog.core.count)
    }

    @Test
    func energyBalanceHasBothMetrics() {
        let balance = EnergyBalanceCalculator().calculate(intakeKcal: 1800, activeKcal: 500, basalKcal: 1500, balanceGoalKcal: -300)
        #expect(balance.totalBurnKcal == 2000)
        #expect(balance.activeBalanceKcal == 1300)
        #expect(balance.totalBalanceKcal == -200)
        #expect(balance.suggestedIntakeKcal == 1700)
        #expect(balance.isComplete)
    }

    @Test
    func catalogFindsChineseAlias() async {
        let catalog = FoodCatalog()
        let results = await catalog.search(query: "地瓜")
        #expect(results.first?.name == "红薯")
    }

    @Test
    func latteNamePrefersLatteNotIcedCoffee() async {
        let catalog = FoodCatalog()
        let matcher = PhotoFoodMatcher(catalog: catalog)
        let dish = AnalyzedDish(
            name: "流心芝士拿铁（冰，无焦糖）",
            visibleIngredients: ["牛奶", "咖啡"],
            portionMinGrams: 250,
            portionMaxGrams: 350,
            confidence: 0.8
        )
        let matches = await matcher.candidates(for: dish)
        #expect(matches.first?.food.name == "拿铁咖啡")
        #expect(matches.first?.matchedTerm == "拿铁")
    }

    @Test
    func photoMatcherReturnsCandidates() async {
        let catalog = FoodCatalog()
        let matcher = PhotoFoodMatcher(catalog: catalog)
        let dish = AnalyzedDish(name: "米饭", visibleIngredients: ["鸡蛋"], portionMinGrams: 80, portionMaxGrams: 140, confidence: 0.8)
        let matches = await matcher.candidates(for: dish)
        #expect(!matches.isEmpty)
        #expect(matches.count <= 3)
    }

    @Test
    func backupRoundTrips() throws {
        let service = DataTransferService()
        let data = try service.makeJSONBackup(entries: [], energyDays: [], goals: [])
        let decoded = try service.decodeJSONBackup(data)
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.entries.isEmpty)
        let csv = service.makeCSV(entries: [])
        #expect(csv.starts(with: Data([0xEF, 0xBB, 0xBF])))
    }

    @Test
    func dayKeyRespectsTimeZone() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(DayKey.make(from: date, timeZone: TimeZone(secondsFromGMT: 0)!) == "1970-01-01")
        #expect(DayKey.make(from: date, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!) == "1970-01-01")
    }
}

struct FoodMatchingRegressionTests {
    private func dish(_ name: String, ingredients: [String] = []) -> AnalyzedDish {
        AnalyzedDish(name: name, visibleIngredients: ingredients, portionMinGrams: 250, portionMaxGrams: 350, confidence: 0.8)
    }

    @Test
    func latteWithPreparationModifiersMatchesLatte() async {
        let matcher = PhotoFoodMatcher(catalog: FoodCatalog())
        let matches = await matcher.candidates(for: dish("流心芝士拿铁（冰，无焦糖）", ingredients: ["牛奶", "咖啡"]))
        #expect(matches.first?.food.name == "拿铁咖啡")
        #expect(matches.first?.matchedTerm == "拿铁")
        #expect(PhotoFoodMatcher.preferredCandidate(from: matches)?.food.name == "拿铁咖啡")
    }

    @Test
    func icedAmericanoMatchesIcedCoffee() async {
        let matcher = PhotoFoodMatcher(catalog: FoodCatalog())
        let matches = await matcher.candidates(for: dish("冰美式", ingredients: ["咖啡"]))
        #expect(matches.first?.food.name == "无糖冰咖啡")
    }

    @Test
    func genericCoffeeRequiresManualSelection() async {
        let matcher = PhotoFoodMatcher(catalog: FoodCatalog())
        let matches = await matcher.candidates(for: dish("咖啡"))
        #expect(matches.count >= 2)
        #expect(PhotoFoodMatcher.preferredCandidate(from: matches) == nil)
    }

    @Test
    func blackCoffeePrefersAmericano() async {
        let matcher = PhotoFoodMatcher(catalog: FoodCatalog())
        let matches = await matcher.candidates(for: dish("黑咖啡"))
        #expect(matches.first?.food.name == "美式咖啡")
    }
}
