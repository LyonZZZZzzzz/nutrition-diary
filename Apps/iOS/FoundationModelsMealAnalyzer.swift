import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import NutritionKit

@Generable(description: "一张餐食照片的结构化分析")
private struct GeneratedDish {
    var name: String
    var visibleIngredients: [String]
    var cookingMethod: String?
    var portionMinGrams: Double
    var portionMaxGrams: Double
    var hiddenOilLevel: String?
    var confidence: Double
    var uncertaintyNotes: [String]
}

@Generable(description: "餐食照片分析结果")
private struct GeneratedMealAnalysis {
    var dishes: [GeneratedDish]
    var overallConfidence: Double
    var analysisNote: String
}

struct FoundationModelsMealAnalyzer: MealPhotoAnalyzing {
    func availability(language: AppLanguage = .simplifiedChinese) async -> PhotoAnalysisAvailability {
        let model = SystemLanguageModel.default
        guard model.capabilities.contains(.vision) else { return .unavailable }
        if !model.supportsLocale(Locale(identifier: language.rawValue)) {
            return .localeUnsupported
        }
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceDisabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailable
            }
        @unknown default:
            return .unavailable
        }
    }

    func analyze(images: [Data], language: AppLanguage = .simplifiedChinese) async throws -> AnalyzedMeal {
        let availability = await availability(language: language)
        guard availability == .available else {
            throw PhotoAnalysisError.unavailable(availability)
        }
        guard !images.isEmpty, images.count <= 3 else {
            throw PhotoAnalysisError.invalidImage
        }

        let attachments = try images.enumerated().map { index, data in
            try makeAttachment(
                data: data,
                label: language.isChinese
                    ? (index == 0 ? "餐食全景" : "餐食近景 \(index)")
                    : (index == 0 ? "Full meal view" : "Meal close-up \(index)")
            )
        }
        let promptText = language.isChinese
            ? """
              请识别这些餐食照片中的所有菜品和可见食材。只描述图片中能够观察到的内容，
              给出合理的可食份量范围、烹饪方式和隐藏油汁程度，不要直接估算热量。
              如果无法判断份量，请扩大范围并降低置信度。
              """
            : """
              Identify every dish and visible ingredient in these meal photos. Describe only what is visible,
              provide a reasonable edible-portion range, cooking method, and hidden oil level, and do not estimate calories.
              If portion size is uncertain, widen the range and lower the confidence.
              """
        let prompt = Prompt {
            promptText
            attachments
        }
        let instructions = language.isChinese
            ? """
              你是中文餐食视觉分析助手。输出必须保守、可编辑且明确说明不确定性。
              菜名使用简体中文，份量以克为单位。不要给出营养或医疗建议。
              """
            : """
              You are an English-language meal vision assistant. Outputs must be conservative, editable, and explicit about uncertainty.
              Use English dish names and grams for portion sizes. Never provide nutrition or medical advice.
              """
        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let response = try await session.respond(to: prompt, generating: GeneratedMealAnalysis.self)
            let generated = response.content
            let dishes = generated.dishes.map { dish in
                AnalyzedDish(
                    name: dish.name,
                    visibleIngredients: dish.visibleIngredients,
                    cookingMethod: dish.cookingMethod,
                    portionMinGrams: Decimal(max(1, dish.portionMinGrams)),
                    portionMaxGrams: Decimal(max(dish.portionMinGrams, dish.portionMaxGrams)),
                    hiddenOilLevel: dish.hiddenOilLevel,
                    confidence: min(max(dish.confidence, 0), 1),
                    uncertaintyNotes: dish.uncertaintyNotes
                )
            }
            guard !dishes.isEmpty else {
                throw PhotoAnalysisError.modelFailure(language.isChinese ? "未识别到可确认的菜品" : "No confirmable dishes were recognized")
            }
            return AnalyzedMeal(
                dishes: dishes,
                overallConfidence: min(max(generated.overallConfidence, 0), 1),
                analysisNote: generated.analysisNote
            )
        } catch let error as PhotoAnalysisError {
            throw error
        } catch {
            throw PhotoAnalysisError.modelFailure(
                language.isChinese
                    ? "设备端照片分析失败：\(error.localizedDescription)"
                    : "On-device photo analysis failed: \(error.localizedDescription)"
            )
        }
    }

    private func makeAttachment(data: Data, label: String) throws -> Attachment<ImageAttachmentContent> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoAnalysisError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoAnalysisError.invalidImage
        }
        return Attachment<ImageAttachmentContent>(image).label(label)
    }
}
