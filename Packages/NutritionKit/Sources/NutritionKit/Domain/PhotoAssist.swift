import Foundation

public struct NormalizedImageRegion: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        let safeX = min(max(x, 0), 1)
        let safeY = min(max(y, 0), 1)
        self.x = safeX
        self.y = safeY
        self.width = min(max(width, 0), 1 - safeX)
        self.height = min(max(height, 0), 1 - safeY)
    }

    public var isValid: Bool { width >= 0.02 && height >= 0.02 }
}

public enum PlatewareSpec: String, Codable, CaseIterable, Identifiable, Sendable {
    case smallBowl
    case riceBowl
    case soupBowl
    case plate20cm
    case plate25cm
    case cup250ml
    case cup350ml
    case cup450ml
    case packagedServing

    public var id: String { rawValue }

    public var portionRangeGrams: ClosedRange<Double> {
        switch self {
        case .smallBowl: 100...180
        case .riceBowl: 180...280
        case .soupBowl: 280...450
        case .plate20cm: 120...260
        case .plate25cm: 180...380
        case .cup250ml: 220...290
        case .cup350ml: 300...390
        case .cup450ml: 380...500
        case .packagedServing: 20...500
        }
    }

    public var confidence: Double {
        switch self {
        case .smallBowl, .riceBowl, .plate20cm, .plate25cm, .cup250ml, .cup350ml: 0.78
        case .soupBowl, .cup450ml: 0.72
        case .packagedServing: 0.65
        }
    }

    public func localizedTitle(for language: AppLanguage) -> String {
        if language.isChinese {
            switch self {
            case .smallBowl: "小碗"
            case .riceBowl: "饭碗"
            case .soupBowl: "汤碗"
            case .plate20cm: "20 厘米盘"
            case .plate25cm: "25 厘米盘"
            case .cup250ml: "250 毫升杯"
            case .cup350ml: "350 毫升杯"
            case .cup450ml: "450 毫升杯"
            case .packagedServing: "包装每份重量"
            }
        } else {
            switch self {
            case .smallBowl: "Small bowl"
            case .riceBowl: "Rice bowl"
            case .soupBowl: "Soup bowl"
            case .plate20cm: "20 cm plate"
            case .plate25cm: "25 cm plate"
            case .cup250ml: "250 ml cup"
            case .cup350ml: "350 ml cup"
            case .cup450ml: "450 ml cup"
            case .packagedServing: "Packaged serving"
            }
        }
    }
}

public struct PhotoSecondPassRequest: Codable, Hashable, Sendable {
    public let targetDishNames: [String]
    public let plateware: PlatewareSpec?

    public init(targetDishNames: [String], plateware: PlatewareSpec? = nil) {
        self.targetDishNames = targetDishNames
        self.plateware = plateware
    }
}

public struct PhotoCandidateDecision: Hashable, Sendable {
    public let automaticSelection: PhotoFoodMatch?
    public let topGap: Double
    public let requiresManualReview: Bool

    public init(automaticSelection: PhotoFoodMatch?, topGap: Double, requiresManualReview: Bool) {
        self.automaticSelection = automaticSelection
        self.topGap = topGap
        self.requiresManualReview = requiresManualReview
    }
}

public enum PhotoCandidateSelector {
    public static func decide(
        from candidates: [PhotoFoodMatch],
        minimumScore: Double = 0.80,
        minimumGap: Double = 0.10
    ) -> PhotoCandidateDecision {
        guard let first = candidates.first else {
            return PhotoCandidateDecision(automaticSelection: nil, topGap: 0, requiresManualReview: true)
        }
        let gap = first.score - (candidates.dropFirst().first?.score ?? 0)
        let accepted = first.score >= minimumScore && gap >= minimumGap
        return PhotoCandidateDecision(
            automaticSelection: accepted ? first : nil,
            topGap: max(0, gap),
            requiresManualReview: !accepted
        )
    }
}

public enum PhotoRecognitionGate {
    public static func requiresSecondPass(
        meal: AnalyzedMeal,
        topCandidateScores: [Double],
        minimumConfidence: Double = 0.80,
        minimumCandidateGap: Double = 0.12
    ) -> Bool {
        if meal.dishes.count > 1 { return true }
        if meal.overallConfidence < minimumConfidence { return true }
        if meal.dishes.contains(where: {
            $0.confidence < minimumConfidence || portionSpanIsUnusual($0)
        }) { return true }
        guard let top = topCandidateScores.first else { return true }
        let gap = top - (topCandidateScores.dropFirst().first ?? 0)
        return top < minimumConfidence || gap < minimumCandidateGap
    }

    public static func secondPassDishIndexes(
        meal: AnalyzedMeal,
        topCandidateScoresByDish: [[Double]],
        minimumConfidence: Double = 0.80,
        minimumCandidateGap: Double = 0.12
    ) -> [Int] {
        meal.dishes.indices.filter { index in
            let dish = meal.dishes[index]
            if dish.confidence < minimumConfidence || portionSpanIsUnusual(dish) { return true }
            let scores = topCandidateScoresByDish.indices.contains(index) ? topCandidateScoresByDish[index] : []
            guard let top = scores.first else { return true }
            let gap = top - (scores.dropFirst().first ?? 0)
            return top < minimumConfidence || gap < minimumCandidateGap
        }.prefix(3).map { $0 }
    }

    private static func portionSpanIsUnusual(_ dish: AnalyzedDish) -> Bool {
        let minimum = NSDecimalNumber(decimal: dish.portionMinGrams).doubleValue
        let maximum = NSDecimalNumber(decimal: dish.portionMaxGrams).doubleValue
        return minimum > 0 && maximum / minimum > 2.5
    }
}

public enum PhotoSecondPassMerger {
    public static func merge(primary: AnalyzedMeal, secondPass: AnalyzedMeal, targetIndexes: [Int]) -> AnalyzedMeal {
        guard !secondPass.dishes.isEmpty, !targetIndexes.isEmpty else { return primary }
        var dishes = primary.dishes
        for (offset, index) in targetIndexes.enumerated() where dishes.indices.contains(index) {
            guard secondPass.dishes.indices.contains(offset) else { break }
            let refined = secondPass.dishes[offset]
            dishes[index] = AnalyzedDish(
                id: dishes[index].id,
                name: refined.name,
                visibleIngredients: refined.visibleIngredients,
                cookingMethod: refined.cookingMethod,
                portionMinGrams: refined.portionMinGrams,
                portionMaxGrams: refined.portionMaxGrams,
                hiddenOilLevel: refined.hiddenOilLevel,
                confidence: refined.confidence,
                uncertaintyNotes: refined.uncertaintyNotes,
                candidateAliases: refined.candidateAliases,
                normalizedRegion: refined.normalizedRegion ?? dishes[index].normalizedRegion,
                plateware: refined.plateware ?? dishes[index].plateware,
                portionConfidence: refined.portionConfidence
            )
        }
        return AnalyzedMeal(
            dishes: dishes,
            overallConfidence: max(primary.overallConfidence, secondPass.overallConfidence),
            analysisNote: secondPass.analysisNote,
            createdAt: primary.createdAt
        )
    }
}

public struct PhotoPortionSuggestion: Hashable, Sendable {
    public let minimumGrams: Double
    public let maximumGrams: Double
    public let suggestedGrams: Double
    public let confidence: Double
    public let usedHistory: Bool

    public init(minimumGrams: Double, maximumGrams: Double, suggestedGrams: Double, confidence: Double, usedHistory: Bool) {
        self.minimumGrams = minimumGrams
        self.maximumGrams = maximumGrams
        self.suggestedGrams = suggestedGrams
        self.confidence = confidence
        self.usedHistory = usedHistory
    }
}

public enum PhotoPortionEstimator {
    public static func suggest(
        dish: AnalyzedDish,
        plateware: PlatewareSpec?,
        historyMedianGrams: Double? = nil
    ) -> PhotoPortionSuggestion {
        let visualMin = NSDecimalNumber(decimal: dish.portionMinGrams).doubleValue
        let visualMax = NSDecimalNumber(decimal: dish.portionMaxGrams).doubleValue
        let modelMidpoint = (visualMin + visualMax) / 2
        var lower = visualMin
        var upper = visualMax
        var confidence = dish.portionConfidence ?? dish.confidence

        if let plateware {
            lower = max(visualMin, plateware.portionRangeGrams.lowerBound)
            upper = min(visualMax, plateware.portionRangeGrams.upperBound)
            if lower > upper {
                lower = min(visualMin, plateware.portionRangeGrams.lowerBound)
                upper = max(visualMax, plateware.portionRangeGrams.upperBound)
            }
            confidence = min(1, max(0, (confidence * 0.65) + (plateware.confidence * 0.35)))
        } else {
            lower = visualMin * 0.80
            upper = visualMax * 1.20
            confidence *= 0.72
        }

        var suggested = (lower + upper) / 2
        let usedHistory = historyMedianGrams != nil
        if let historyMedianGrams, historyMedianGrams > 0 {
            suggested = historyMedianGrams * 0.70 + modelMidpoint * 0.30
        }
        suggested = min(max(suggested, lower * 0.80), upper * 1.20)
        return PhotoPortionSuggestion(
            minimumGrams: max(1, lower),
            maximumGrams: max(max(1, lower), upper),
            suggestedGrams: max(1, suggested),
            confidence: min(max(confidence, 0), 1),
            usedHistory: usedHistory
        )
    }
}

public enum PhotoImageQualityIssue: String, Codable, Hashable, Sendable {
    case tooDark
    case tooBright
    case lowContrast
    case likelyBlurry
    case subjectTooSmall

    public func localizedDescription(for language: AppLanguage) -> String {
        if language.isChinese {
            switch self {
            case .tooDark: "照片过暗，请在光线更充足处补拍"
            case .tooBright: "照片过曝，请避开强反光后补拍"
            case .lowContrast: "照片对比度不足，请靠近食物补拍"
            case .likelyBlurry: "照片可能模糊，请保持手机稳定后补拍"
            case .subjectTooSmall: "食物在画面中过小，请靠近或裁切后补拍"
            }
        } else {
            switch self {
            case .tooDark: "The photo is too dark; retake it in better light."
            case .tooBright: "The photo is overexposed; retake it away from glare."
            case .lowContrast: "The photo has low contrast; move closer and retake it."
            case .likelyBlurry: "The photo may be blurry; hold the phone steady and retake it."
            case .subjectTooSmall: "The food is too small in frame; move closer or crop and retake it."
            }
        }
    }
}
