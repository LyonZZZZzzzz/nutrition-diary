import Foundation
import NutritionKit

@MainActor
protocol EnergyReading {
    func requestAuthorization() async throws
    func readDailyEnergy(for date: Date, timeZone: TimeZone, preferredSourceID: String?) async throws -> HealthEnergyReadResult
}

@MainActor
protocol HealthEnergyObserving {
    func startObserving(onChange: @escaping @Sendable () async -> Void)
    func stopObserving()
}

@MainActor
protocol DietaryHealthWriting {
    func syncMeal(dayKey: String, mealType: MealType, entries: [DiaryEntry], allowEstimated: Bool) async throws
}

struct PhotoReviewItem: Identifiable {
    let id = UUID()
    let dish: AnalyzedDish
    var candidates: [PhotoFoodMatch]
    var selectedFood: FoodItem?
    var grams: Decimal
    var include: Bool = true
    var plateware: PlatewareSpec? = nil
    var originalSelectedFoodID: UUID? = nil
    var portionSuggestion: PhotoPortionSuggestion? = nil
}

struct PhotoAnalysisReview {
    let analyzedMeal: AnalyzedMeal
    var items: [PhotoReviewItem]
    let localPhotoFilenames: [String]
    let provider: PhotoRecognitionProvider
    var analysisPasses: Int = 1
    var secondPassNote: String? = nil
}

struct PackagedLabelReview {
    var brand: String
    var productName: String
    var referenceUnit: FoodReferenceUnit
    var nutrients: [NutrientMeasurement]
    var consumedAmount: Decimal
    var confidence: Double
    var analysisNote: String
    let localPhotoFilenames: [String]

    func value(for nutrient: NutrientID) -> Double? {
        nutrients.first { $0.nutrient == nutrient }?.doubleValue
    }

    mutating func setValue(_ value: Double?, for nutrient: NutrientID) {
        guard let index = nutrients.firstIndex(where: { $0.nutrient == nutrient }) else { return }
        let unit = nutrients[index].unit
        if let value, value.isFinite, value >= 0 {
            nutrients[index] = NutrientMeasurement(
                nutrient: nutrient,
                value: Decimal(value),
                unit: unit,
                status: .estimated,
                source: .photoEstimate
            )
        } else {
            nutrients[index] = .missing(nutrient, unit: unit, source: .photoEstimate)
        }
    }
}

protocol DeepSeekPhotoAnalyzing: FoodPhotoAnalyzing {
    func testAPIKey(_ apiKey: String) async throws
    func analyzeSecondPass(
        images: [Data],
        regions: [NormalizedImageRegion],
        request: PhotoSecondPassRequest,
        apiKey: String,
        language: AppLanguage
    ) async throws -> AnalyzedMeal
}

enum HealthReadError: Error, LocalizedError {
    case authorizationRequired
    case unavailable

    var errorDescription: String? {
        switch self {
        case .authorizationRequired: "尚未授权读取健康数据"
        case .unavailable: "HealthKit 当前不可用"
        }
    }
}

@MainActor
func localizedApplicationError(_ error: Error, language: AppLanguage) -> String {
    if let error = error as? DeepSeekCredentialError {
        switch error {
        case .keychain(let status):
            return language.isChinese
                ? "无法访问 DeepSeek API Key（Keychain 错误 \(status)）"
                : "Could not access the DeepSeek API key (Keychain error \(status))"
        }
    }
    if let error = error as? HealthReadError {
        switch error {
        case .authorizationRequired:
            return language.isChinese ? "尚未授权读取健康数据" : "Health data access has not been authorized"
        case .unavailable:
            return language.isChinese ? "HealthKit 当前不可用" : "HealthKit is currently unavailable"
        }
    }
    return localizedErrorDescription(error, language: language)
}
