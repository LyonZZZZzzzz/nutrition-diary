import Foundation
import Testing
@testable import NutritionKit

struct PhotoAccuracyTests {
    private func dish(
        name: String = "番茄炒蛋",
        minimum: Decimal = 120,
        maximum: Decimal = 180,
        confidence: Double = 0.86,
        region: NormalizedImageRegion? = nil
    ) -> AnalyzedDish {
        AnalyzedDish(
            name: name,
            visibleIngredients: ["番茄", "鸡蛋"],
            portionMinGrams: minimum,
            portionMaxGrams: maximum,
            confidence: confidence,
            normalizedRegion: region
        )
    }

    private func match(food: FoodItem, score: Double) -> PhotoFoodMatch {
        PhotoFoodMatch(dish: dish(), food: food, score: score, matchedTerm: food.localizedName(for: .simplifiedChinese))
    }

    @Test
    func candidateSelectionRequiresBothScoreAndGap() {
        let foodA = SeedCatalog.foods[0]
        let foodB = SeedCatalog.foods[1]
        let accepted = PhotoCandidateSelector.decide(from: [match(food: foodA, score: 0.91), match(food: foodB, score: 0.78)])
        #expect(accepted.automaticSelection?.food.id == foodA.id)

        let ambiguous = PhotoCandidateSelector.decide(from: [match(food: foodA, score: 0.91), match(food: foodB, score: 0.85)])
        #expect(ambiguous.automaticSelection == nil)
        #expect(ambiguous.requiresManualReview)

        let weak = PhotoCandidateSelector.decide(from: [match(food: foodA, score: 0.79), match(food: foodB, score: 0.50)])
        #expect(weak.automaticSelection == nil)
    }

    @Test
    func secondPassTriggerCoversMultiDishLowConfidenceAndWideRange() {
        let singleConfident = AnalyzedMeal(dishes: [dish(confidence: 0.92)], overallConfidence: 0.9, analysisNote: "ok")
        #expect(!PhotoRecognitionGate.requiresSecondPass(meal: singleConfident, topCandidateScores: [0.92, 0.70]))

        let lowConfidence = AnalyzedMeal(dishes: [dish(confidence: 0.72)], overallConfidence: 0.72, analysisNote: "low")
        #expect(PhotoRecognitionGate.requiresSecondPass(meal: lowConfidence, topCandidateScores: [0.9, 0.6]))

        let wideRange = AnalyzedMeal(dishes: [dish(minimum: 50, maximum: 200)], overallConfidence: 0.9, analysisNote: "wide")
        #expect(PhotoRecognitionGate.requiresSecondPass(meal: wideRange, topCandidateScores: [0.9, 0.6]))

        let multi = AnalyzedMeal(dishes: [dish(name: "鱼香肉丝"), dish(name: "米饭")], overallConfidence: 0.9, analysisNote: "multi")
        #expect(PhotoRecognitionGate.requiresSecondPass(meal: multi, topCandidateScores: [0.9, 0.6]))
    }

    @Test
    func secondPassMergesOnlyTargetDishesAndPreservesIdentity() {
        let primaryDish = dish(name: "番茄炒蛋", region: NormalizedImageRegion(x: 0.1, y: 0.1, width: 0.4, height: 0.4))
        let primary = AnalyzedMeal(dishes: [primaryDish, dish(name: "米饭")], overallConfidence: 0.7, analysisNote: "first")
        let refined = AnalyzedMeal(
            dishes: [dish(name: "番茄炒鸡蛋", minimum: 150, maximum: 200, confidence: 0.92)],
            overallConfidence: 0.92,
            analysisNote: "second"
        )
        let merged = PhotoSecondPassMerger.merge(primary: primary, secondPass: refined, targetIndexes: [0])
        #expect(merged.dishes[0].id == primaryDish.id)
        #expect(merged.dishes[0].name == "番茄炒鸡蛋")
        #expect(merged.dishes[1].name == "米饭")
        #expect(merged.overallConfidence == 0.92)
    }

    @Test
    func platewareAndHistoryShapePortionSuggestionWithinBounds() {
        let analyzed = dish(minimum: 80, maximum: 200, confidence: 0.84)
        let withoutPlate = PhotoPortionEstimator.suggest(dish: analyzed, plateware: nil)
        #expect(withoutPlate.minimumGrams < 80)
        #expect(withoutPlate.maximumGrams > 200)
        #expect(withoutPlate.confidence < 0.84)

        let withPlate = PhotoPortionEstimator.suggest(dish: analyzed, plateware: .riceBowl, historyMedianGrams: 350)
        #expect(withPlate.minimumGrams == 180)
        #expect(withPlate.maximumGrams == 200)
        #expect(withPlate.suggestedGrams <= 240)
        #expect(withPlate.usedHistory)
    }

    @Test
    func thirtyWeighedFixtureMealsStayWithinMedianAbsoluteErrorTarget() {
        let actualWeights = [
            85.0, 95, 110, 120, 130, 145, 160, 175, 190, 205,
            220, 235, 245, 260, 275, 290, 305, 320, 335, 350,
            365, 380, 395, 410, 425, 440, 455, 470, 485, 500
        ]
        let estimates = actualWeights.enumerated().map { index, actual in
            let bias = Double((index % 7) - 3) * 0.02
            let midpoint = actual * (1 + bias)
            let analyzed = dish(minimum: Decimal(midpoint * 0.75), maximum: Decimal(midpoint * 1.25), confidence: 0.85)
            return PhotoPortionEstimator.suggest(dish: analyzed, plateware: nil).suggestedGrams
        }
        let errors = zip(estimates, actualWeights).map { abs($0 - $1) / $1 }.sorted()
        let median = errors[errors.count / 2]
        #expect(median <= 0.30)
    }

    @Test
    func localLearningRaisesAndLowersCandidatesWithoutStoringQueryText() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-learning-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PhotoMatchLearningStore(fileURL: fileURL)
        let selected = SeedCatalog.foods[0].id
        let rejected = SeedCatalog.foods[1].id

        #expect(await store.rankingBonus(query: "私密菜名", foodID: selected) == 0)
        for _ in 0..<2 {
            await store.recordDecision(
                query: "私密菜名",
                selectedFoodID: selected,
                rejectedFoodID: rejected,
                selectedGrams: 180,
                modelMidpointGrams: 150
            )
        }
        #expect(await store.rankingBonus(query: "私密菜名", foodID: selected) > 0.14)
        #expect(await store.rankingBonus(query: "私密菜名", foodID: rejected) < 0)

        await store.recordDecision(
            query: "私密菜名",
            selectedFoodID: selected,
            rejectedFoodID: nil,
            selectedGrams: 150,
            modelMidpointGrams: 150
        )
        let median = await store.portionMedianRatio(query: "私密菜名", foodID: selected)
        #expect(median != nil)
        let persisted = (try? Data(contentsOf: fileURL)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!persisted.contains("私密菜名"))
    }

    @Test
    func legacyAnalyzedDishDecodesWithoutNewOptionalFields() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"米饭","visibleIngredients":[],"portionMinGrams":100,"portionMaxGrams":150,"confidence":0.8,"uncertaintyNotes":[]}
        """
        let decoded = try JSONDecoder().decode(AnalyzedDish.self, from: Data(json.utf8))
        #expect(decoded.name == "米饭")
        #expect(decoded.candidateAliases == nil)
        #expect(decoded.normalizedRegion == nil)
    }

    @Test
    func matcherUsesCandidateAliasesForPreparedDish() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let matcher = PhotoFoodMatcher(catalog: catalog, language: .simplifiedChinese)
        let aliasedDish = AnalyzedDish(
            name: "家常菜",
            visibleIngredients: ["番茄", "鸡蛋"],
            portionMinGrams: 150,
            portionMaxGrams: 250,
            confidence: 0.82,
            candidateAliases: ["西红柿炒鸡蛋"]
        )
        let candidates = await matcher.candidates(for: aliasedDish, limit: 3)
        #expect(candidates.contains { $0.food.nameZh == "番茄炒蛋" })
    }
}
