import Foundation

public struct MealPhoto: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let localFilename: String
    public let contentHash: String
    public let capturedAt: Date

    public init(id: UUID = UUID(), localFilename: String, contentHash: String, capturedAt: Date = .now) {
        self.id = id
        self.localFilename = localFilename
        self.contentHash = contentHash
        self.capturedAt = capturedAt
    }
}

public struct AnalyzedDish: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let visibleIngredients: [String]
    public let cookingMethod: String?
    public let portionMinGrams: Decimal
    public let portionMaxGrams: Decimal
    public let hiddenOilLevel: String?
    public let confidence: Double
    public let uncertaintyNotes: [String]
    public let candidateAliases: [String]?
    public let normalizedRegion: NormalizedImageRegion?
    public let plateware: PlatewareSpec?
    public let portionConfidence: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        visibleIngredients: [String],
        cookingMethod: String? = nil,
        portionMinGrams: Decimal,
        portionMaxGrams: Decimal,
        hiddenOilLevel: String? = nil,
        confidence: Double,
        uncertaintyNotes: [String] = [],
        candidateAliases: [String]? = nil,
        normalizedRegion: NormalizedImageRegion? = nil,
        plateware: PlatewareSpec? = nil,
        portionConfidence: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.visibleIngredients = visibleIngredients
        self.cookingMethod = cookingMethod
        self.portionMinGrams = portionMinGrams
        self.portionMaxGrams = portionMaxGrams
        self.hiddenOilLevel = hiddenOilLevel
        self.confidence = confidence
        self.uncertaintyNotes = uncertaintyNotes
        self.candidateAliases = candidateAliases
        self.normalizedRegion = normalizedRegion
        self.plateware = plateware
        self.portionConfidence = portionConfidence
    }

    public var suggestedGrams: Decimal {
        (portionMinGrams + portionMaxGrams) / 2
    }
}

public struct AnalyzedMeal: Codable, Hashable, Sendable {
    public let dishes: [AnalyzedDish]
    public let overallConfidence: Double
    public let analysisNote: String
    public let createdAt: Date

    public init(dishes: [AnalyzedDish], overallConfidence: Double, analysisNote: String, createdAt: Date = .now) {
        self.dishes = dishes
        self.overallConfidence = overallConfidence
        self.analysisNote = analysisNote
        self.createdAt = createdAt
    }
}

public struct PhotoFoodMatch: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let dish: AnalyzedDish
    public let food: FoodItem
    public let score: Double
    public let matchedTerm: String

    public init(id: UUID = UUID(), dish: AnalyzedDish, food: FoodItem, score: Double, matchedTerm: String) {
        self.id = id
        self.dish = dish
        self.food = food
        self.score = score
        self.matchedTerm = matchedTerm
    }
}

public enum PhotoAnalysisAvailability: String, Codable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceDisabled
    case modelNotReady
    case localeUnsupported
    case unavailable
}

public enum PhotoAnalysisError: Error, LocalizedError, Sendable {
    case unavailable(PhotoAnalysisAvailability)
    case invalidImage
    case imageQuality(PhotoImageQualityIssue)
    case modelFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            switch reason {
            case .available: "设备端照片识别不可用"
            case .deviceNotEligible: "当前设备不支持 Apple Intelligence"
            case .appleIntelligenceDisabled: "请先在系统设置中开启 Apple Intelligence"
            case .modelNotReady: "端侧模型尚未准备完成"
            case .localeUnsupported: "当前语言暂不受端侧模型支持"
            case .unavailable: "设备端照片识别不可用"
            }
        case .invalidImage: "照片格式无效"
        case .imageQuality(let issue): issue.localizedDescription(for: .simplifiedChinese)
        case .modelFailure(let message): message
        }
    }
}

public protocol MealPhotoAnalyzing: Sendable {
    func availability(language: AppLanguage) async -> PhotoAnalysisAvailability
    func analyze(images: [Data], language: AppLanguage) async throws -> AnalyzedMeal
}


public enum PhotoRecognitionMode: String, Codable, CaseIterable, Sendable {
    case meal
    case packagedLabel

    public var title: String {
        switch self {
        case .meal: "混合餐"
        case .packagedLabel: "包装营养标签"
        }
    }
}

public enum PhotoRecognitionProvider: String, Codable, Sendable {
    case appleOnDevice
    case deepSeek

    public var title: String {
        switch self {
        case .appleOnDevice: "Apple 本机识别"
        case .deepSeek: "DeepSeek 云端识别"
        }
    }
}

public struct PackagedLabelAnalysis: Codable, Hashable, Sendable {
    public let brand: String?
    public let productName: String
    public let referenceAmount: Decimal
    public let referenceUnit: FoodReferenceUnit
    public let nutrients: [NutrientMeasurement]
    public let confidence: Double
    public let analysisNote: String

    public init(
        brand: String?,
        productName: String,
        referenceAmount: Decimal = 100,
        referenceUnit: FoodReferenceUnit,
        nutrients: [NutrientMeasurement],
        confidence: Double,
        analysisNote: String
    ) {
        self.brand = brand
        self.productName = productName
        self.referenceAmount = referenceAmount
        self.referenceUnit = referenceUnit
        self.nutrients = nutrients
        self.confidence = confidence
        self.analysisNote = analysisNote
    }
}

public enum FoodPhotoAnalysisResult: Codable, Hashable, Sendable {
    case meal(AnalyzedMeal)
    case packagedLabel(PackagedLabelAnalysis)
}

public protocol FoodPhotoAnalyzing: Sendable {
    func analyze(images: [Data], mode: PhotoRecognitionMode, apiKey: String, language: AppLanguage) async throws -> FoodPhotoAnalysisResult
}

public enum DeepSeekVisionError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case unauthorized
    case insufficientBalance
    case rateLimited(retryAfter: TimeInterval?)
    case payloadTooLarge
    case invalidResponse
    case invalidLabel(String)
    case network(String)
    case server(statusCode: Int, requestID: String?)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "尚未配置 DeepSeek API Key"
        case .unauthorized: "DeepSeek API Key 无效，请在设置中重新配置"
        case .insufficientBalance: "DeepSeek 账户余额不足"
        case .rateLimited(let retryAfter):
            retryAfter.map { "DeepSeek 请求过于频繁，请等待约 \(Int($0.rounded())) 秒" } ?? "DeepSeek 请求过于频繁，请稍后重试"
        case .payloadTooLarge: "照片过大，请减少照片数量或重新拍摄"
        case .invalidResponse: "DeepSeek 返回了无法识别的响应"
        case .invalidLabel(let message): message
        case .network(let message): "DeepSeek 网络错误：\(message)"
        case .server(let statusCode, let requestID):
            requestID.map { "DeepSeek 服务错误 \(statusCode)，请求编号 \($0)" } ?? "DeepSeek 服务错误 \(statusCode)"
        case .invalidJSON(let message): "DeepSeek 结果解析失败：\(message)"
        }
    }
}
