import Foundation

public enum FoodReferenceUnit: String, Codable, Hashable, Sendable {
    case gram = "g"
    case milliliter = "ml"
}

public enum FoodNameLocalizationOrigin: String, Codable, Hashable, Sendable {
    case curated
    case taiwanFDA
    case localMachineTranslation
    case original
}

public enum FoodPreparationState: String, Codable, Hashable, Sendable {
    case raw
    case prepared
    case packaged
    case beverage
    case condiment
}

public enum FoodDataQuality: String, Codable, Hashable, Sendable {
    case authoritative
    case curated
    case imported
    case machineTranslated
}

public enum FoodSourceKind: String, Codable, Hashable, Sendable {
    case bundled
    case custom
    case openFoodFacts
    case deepSeekPhotoLabel
    case imported
}

public struct FoodSource: Codable, Hashable, Sendable {
    public let kind: FoodSourceKind
    public let identifier: String?
    public let title: String
    public let titleZh: String?
    public let titleEn: String?
    public let license: String?
    public let sourceURL: URL?
    public let retrievedAt: Date?

    public init(
        kind: FoodSourceKind,
        identifier: String? = nil,
        title: String,
        titleZh: String? = nil,
        titleEn: String? = nil,
        license: String? = nil,
        sourceURL: URL? = nil,
        retrievedAt: Date? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.titleZh = titleZh
        self.titleEn = titleEn
        self.license = license
        self.sourceURL = sourceURL
        self.retrievedAt = retrievedAt
    }

    public static let seed = FoodSource(kind: .bundled, title: "USDA FoodData Central 公共领域快照")
}

public struct ServingPortion: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let label: String
    public let labelZh: String?
    public let labelEn: String?
    public let amount: Decimal
    public let unit: FoodReferenceUnit
    public let approximate: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        labelZh: String? = nil,
        labelEn: String? = nil,
        amount: Decimal,
        unit: FoodReferenceUnit,
        approximate: Bool = true
    ) {
        self.id = id
        self.label = label
        self.labelZh = labelZh
        self.labelEn = labelEn
        self.amount = amount
        self.unit = unit
        self.approximate = approximate
    }
}

public struct FoodItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var nameZh: String?
    public var nameEn: String?
    public var nameZhOrigin: FoodNameLocalizationOrigin?
    public var aliases: [String]
    public var category: String
    public var categoryZh: String?
    public var categoryEn: String?
    public var referenceAmount: Decimal
    public var referenceUnit: FoodReferenceUnit
    public var edibleRatio: Decimal
    public var densityGramsPerMilliliter: Decimal?
    public var nutrients: [NutrientMeasurement]
    public var portions: [ServingPortion]
    public var source: FoodSource
    public var barcode: String?
    public var isFavorite: Bool
    public var pinyin: [String]?
    public var canonicalGroupID: String?
    public var preparationState: FoodPreparationState?
    public var dataQuality: FoodDataQuality?
    public var searchPriority: Int?
    public var commonality: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        nameZh: String? = nil,
        nameEn: String? = nil,
        nameZhOrigin: FoodNameLocalizationOrigin? = nil,
        aliases: [String] = [],
        category: String,
        categoryZh: String? = nil,
        categoryEn: String? = nil,
        referenceAmount: Decimal = 100,
        referenceUnit: FoodReferenceUnit = .gram,
        edibleRatio: Decimal = 1,
        densityGramsPerMilliliter: Decimal? = nil,
        nutrients: [NutrientMeasurement],
        portions: [ServingPortion] = [],
        source: FoodSource = .seed,
        barcode: String? = nil,
        isFavorite: Bool = false,
        pinyin: [String]? = nil,
        canonicalGroupID: String? = nil,
        preparationState: FoodPreparationState? = nil,
        dataQuality: FoodDataQuality? = nil,
        searchPriority: Int? = nil,
        commonality: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.nameZhOrigin = nameZhOrigin
        self.aliases = aliases
        self.category = category
        self.categoryZh = categoryZh
        self.categoryEn = categoryEn
        self.referenceAmount = referenceAmount
        self.referenceUnit = referenceUnit
        self.edibleRatio = edibleRatio
        self.densityGramsPerMilliliter = densityGramsPerMilliliter
        self.nutrients = nutrients
        self.portions = portions
        self.source = source
        self.barcode = barcode
        self.isFavorite = isFavorite
        self.pinyin = pinyin
        self.canonicalGroupID = canonicalGroupID
        self.preparationState = preparationState
        self.dataQuality = dataQuality
        self.searchPriority = searchPriority
        self.commonality = commonality
    }

    public func portion(id: UUID) -> ServingPortion? {
        portions.first { $0.id == id }
    }
}

public enum FoodQuantity: Codable, Hashable, Sendable {
    case edibleGrams(Decimal)
    case purchasedGrams(Decimal)
    case milliliters(Decimal)
    case portion(id: UUID, count: Decimal)
}
