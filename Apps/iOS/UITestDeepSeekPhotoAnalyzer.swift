#if DEBUG
import Foundation
import NutritionKit

actor UITestDeepSeekPhotoAnalyzer: DeepSeekPhotoAnalyzing {
    private let forcesLowConfidence: Bool

    init(forcesLowConfidence: Bool = false) {
        self.forcesLowConfidence = forcesLowConfidence
    }

    func testAPIKey(_ apiKey: String) async throws {}

    func analyze(images: [Data], mode: PhotoRecognitionMode, apiKey: String, language: AppLanguage) async throws -> FoodPhotoAnalysisResult {
        if mode == .packagedLabel {
            return .packagedLabel(PackagedLabelAnalysis(
                brand: "测试品牌",
                productName: "测试营养饮品",
                referenceUnit: .milliliter,
                nutrients: [
                    NutrientMeasurement(nutrient: NutrientCatalog.energy, value: 42, unit: .kilocalorie, status: .estimated, source: .photoEstimate),
                    NutrientMeasurement(nutrient: NutrientCatalog.protein, value: 3.1, unit: .gram, status: .estimated, source: .photoEstimate)
                ],
                confidence: 0.88,
                analysisNote: "UI test fixture"
            ))
        }
        let dish = AnalyzedDish(
            name: "家常小炒",
            visibleIngredients: ["猪肉", "木耳"],
            cookingMethod: "炒",
            portionMinGrams: 100,
            portionMaxGrams: 260,
            confidence: 0.72,
            uncertaintyNotes: ["需要第二次近景识别"],
            candidateAliases: ["鱼香肉丝"],
            normalizedRegion: NormalizedImageRegion(x: 0.1, y: 0.1, width: 0.6, height: 0.6),
            portionConfidence: 0.66
        )
        return .meal(AnalyzedMeal(dishes: [dish], overallConfidence: 0.72, analysisNote: "UI test first pass"))
    }

    func analyzeSecondPass(
        images: [Data],
        regions: [NormalizedImageRegion],
        request: PhotoSecondPassRequest,
        apiKey: String,
        language: AppLanguage
    ) async throws -> AnalyzedMeal {
        if forcesLowConfidence {
            let dish = AnalyzedDish(
                name: "无法确定的菜品",
                visibleIngredients: ["未知食材"],
                cookingMethod: nil,
                portionMinGrams: 100,
                portionMaxGrams: 300,
                confidence: 0.55,
                uncertaintyNotes: ["候选不足"],
                normalizedRegion: regions.first,
                portionConfidence: 0.40
            )
            return AnalyzedMeal(dishes: [dish], overallConfidence: 0.55, analysisNote: "UI test low confidence")
        }
        let dish = AnalyzedDish(
            name: "鱼香肉丝",
            visibleIngredients: ["猪肉", "木耳", "胡萝卜"],
            cookingMethod: "炒",
            portionMinGrams: 180,
            portionMaxGrams: 260,
            confidence: 0.92,
            candidateAliases: ["鱼香猪肉丝"],
            normalizedRegion: regions.first,
            plateware: request.plateware ?? .plate20cm,
            portionConfidence: 0.86
        )
        return AnalyzedMeal(dishes: [dish], overallConfidence: 0.92, analysisNote: "UI test second pass")
    }
}
#endif
