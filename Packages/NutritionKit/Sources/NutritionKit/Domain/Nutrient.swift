import Foundation

public struct NutrientID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public init(_ value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

public enum NutrientUnit: String, Codable, Sendable {
    case kilocalorie = "kcal"
    case gram = "g"
    case milligram = "mg"
    case microgram = "ug"

    public var symbol: String {
        switch self {
        case .kilocalorie: "kcal"
        case .gram: "g"
        case .milligram: "mg"
        case .microgram: "µg"
        }
    }
}

public enum NutrientStatus: String, Codable, Sendable {
    case complete
    case estimated
    case missing
}

public enum MeasurementSource: String, Codable, Sendable {
    case bundledCatalog
    case userFood
    case recipe
    case photoEstimate
    case importedCatalog
    case manual
}

public enum NutrientGroup: String, Codable, Hashable, Sendable, CaseIterable {
    case macronutrient
    case fatDetail
    case mineral
    case vitamin
    case other

    public var title: String {
        switch self {
        case .macronutrient: "宏量营养"
        case .fatDetail: "脂肪酸与胆固醇"
        case .mineral: "矿物质"
        case .vitamin: "维生素"
        case .other: "其他"
        }
    }
}

public struct NutrientDefinition: Identifiable, Codable, Hashable, Sendable {
    public let id: NutrientID
    public let name: String
    public let unit: NutrientUnit
    public let healthKitIdentifier: String?
    public let displayDigits: Int
    public let group: NutrientGroup

    public init(id: NutrientID, name: String, unit: NutrientUnit, healthKitIdentifier: String? = nil, displayDigits: Int = 1, group: NutrientGroup = .macronutrient) {
        self.id = id
        self.name = name
        self.unit = unit
        self.healthKitIdentifier = healthKitIdentifier
        self.displayDigits = displayDigits
        self.group = group
    }
}

public struct NutrientMeasurement: Codable, Hashable, Sendable {
    public let nutrient: NutrientID
    public let value: Decimal?
    public let unit: NutrientUnit
    public let status: NutrientStatus
    public let source: MeasurementSource

    public init(nutrient: NutrientID, value: Decimal?, unit: NutrientUnit, status: NutrientStatus, source: MeasurementSource) {
        self.nutrient = nutrient
        self.value = value
        self.unit = unit
        self.status = status
        self.source = source
    }

    public static func missing(_ nutrient: NutrientID, unit: NutrientUnit, source: MeasurementSource) -> Self {
        .init(nutrient: nutrient, value: nil, unit: unit, status: .missing, source: source)
    }

    public var doubleValue: Double? { value.map { NSDecimalNumber(decimal: $0).doubleValue } }
}

public enum NutrientCatalog {
    public static let energy = NutrientID("energy_kcal")
    public static let protein = NutrientID("protein_g")
    public static let fat = NutrientID("fat_g")
    public static let carbohydrates = NutrientID("carbohydrate_g")
    public static let fiber = NutrientID("fiber_g")
    public static let sugar = NutrientID("sugar_g")
    public static let sodium = NutrientID("sodium_mg")
    public static let saturatedFat = NutrientID("saturated_fat_g")
    public static let monounsaturatedFat = NutrientID("monounsaturated_fat_g")
    public static let polyunsaturatedFat = NutrientID("polyunsaturated_fat_g")
    public static let transFat = NutrientID("trans_fat_g")
    public static let cholesterol = NutrientID("cholesterol_mg")
    public static let potassium = NutrientID("potassium_mg")
    public static let calcium = NutrientID("calcium_mg")
    public static let iron = NutrientID("iron_mg")
    public static let magnesium = NutrientID("magnesium_mg")
    public static let phosphorus = NutrientID("phosphorus_mg")
    public static let zinc = NutrientID("zinc_mg")
    public static let selenium = NutrientID("selenium_ug")
    public static let vitaminA = NutrientID("vitamin_a_ug")
    public static let vitaminC = NutrientID("vitamin_c_mg")
    public static let vitaminD = NutrientID("vitamin_d_ug")
    public static let vitaminE = NutrientID("vitamin_e_mg")
    public static let vitaminK = NutrientID("vitamin_k_ug")
    public static let thiamin = NutrientID("thiamin_mg")
    public static let riboflavin = NutrientID("riboflavin_mg")
    public static let niacin = NutrientID("niacin_mg")
    public static let vitaminB6 = NutrientID("vitamin_b6_mg")
    public static let folate = NutrientID("folate_ug")
    public static let vitaminB12 = NutrientID("vitamin_b12_ug")
    public static let caffeine = NutrientID("caffeine_mg")

    public static let coreDefinitions: [NutrientDefinition] = [
        .init(id: energy, name: "热量", unit: .kilocalorie, healthKitIdentifier: "dietaryEnergyConsumed", displayDigits: 0),
        .init(id: protein, name: "蛋白质", unit: .gram, healthKitIdentifier: "dietaryProtein"),
        .init(id: fat, name: "脂肪", unit: .gram, healthKitIdentifier: "dietaryFatTotal"),
        .init(id: carbohydrates, name: "碳水化合物", unit: .gram, healthKitIdentifier: "dietaryCarbohydrates"),
        .init(id: fiber, name: "膳食纤维", unit: .gram, healthKitIdentifier: "dietaryFiber"),
        .init(id: sugar, name: "糖", unit: .gram, healthKitIdentifier: "dietarySugar"),
        .init(id: sodium, name: "钠", unit: .milligram, healthKitIdentifier: "dietarySodium", displayDigits: 0)
    ]

    public static let extendedDefinitions: [NutrientDefinition] = [
        .init(id: saturatedFat, name: "饱和脂肪", unit: .gram, healthKitIdentifier: "dietaryFatSaturated", group: .fatDetail),
        .init(id: monounsaturatedFat, name: "单不饱和脂肪", unit: .gram, healthKitIdentifier: "dietaryFatMonounsaturated", group: .fatDetail),
        .init(id: polyunsaturatedFat, name: "多不饱和脂肪", unit: .gram, healthKitIdentifier: "dietaryFatPolyunsaturated", group: .fatDetail),
        .init(id: transFat, name: "反式脂肪", unit: .gram, group: .fatDetail),
        .init(id: cholesterol, name: "胆固醇", unit: .milligram, healthKitIdentifier: "dietaryCholesterol", displayDigits: 0, group: .fatDetail),
        .init(id: potassium, name: "钾", unit: .milligram, healthKitIdentifier: "dietaryPotassium", displayDigits: 0, group: .mineral),
        .init(id: calcium, name: "钙", unit: .milligram, healthKitIdentifier: "dietaryCalcium", displayDigits: 0, group: .mineral),
        .init(id: iron, name: "铁", unit: .milligram, healthKitIdentifier: "dietaryIron", displayDigits: 2, group: .mineral),
        .init(id: magnesium, name: "镁", unit: .milligram, healthKitIdentifier: "dietaryMagnesium", displayDigits: 0, group: .mineral),
        .init(id: phosphorus, name: "磷", unit: .milligram, healthKitIdentifier: "dietaryPhosphorus", displayDigits: 0, group: .mineral),
        .init(id: zinc, name: "锌", unit: .milligram, healthKitIdentifier: "dietaryZinc", displayDigits: 1, group: .mineral),
        .init(id: selenium, name: "硒", unit: .microgram, healthKitIdentifier: "dietarySelenium", displayDigits: 1, group: .mineral),
        .init(id: vitaminA, name: "维生素 A", unit: .microgram, healthKitIdentifier: "dietaryVitaminA", displayDigits: 0, group: .vitamin),
        .init(id: vitaminC, name: "维生素 C", unit: .milligram, healthKitIdentifier: "dietaryVitaminC", displayDigits: 1, group: .vitamin),
        .init(id: vitaminD, name: "维生素 D", unit: .microgram, healthKitIdentifier: "dietaryVitaminD", displayDigits: 1, group: .vitamin),
        .init(id: vitaminE, name: "维生素 E", unit: .milligram, healthKitIdentifier: "dietaryVitaminE", displayDigits: 1, group: .vitamin),
        .init(id: vitaminK, name: "维生素 K", unit: .microgram, healthKitIdentifier: "dietaryVitaminK", displayDigits: 1, group: .vitamin),
        .init(id: thiamin, name: "维生素 B1", unit: .milligram, healthKitIdentifier: "dietaryThiamin", displayDigits: 2, group: .vitamin),
        .init(id: riboflavin, name: "维生素 B2", unit: .milligram, healthKitIdentifier: "dietaryRiboflavin", displayDigits: 2, group: .vitamin),
        .init(id: niacin, name: "烟酸", unit: .milligram, healthKitIdentifier: "dietaryNiacin", displayDigits: 2, group: .vitamin),
        .init(id: vitaminB6, name: "维生素 B6", unit: .milligram, healthKitIdentifier: "dietaryVitaminB6", displayDigits: 2, group: .vitamin),
        .init(id: folate, name: "叶酸", unit: .microgram, healthKitIdentifier: "dietaryFolate", displayDigits: 0, group: .vitamin),
        .init(id: vitaminB12, name: "维生素 B12", unit: .microgram, healthKitIdentifier: "dietaryVitaminB12", displayDigits: 2, group: .vitamin),
        .init(id: caffeine, name: "咖啡因", unit: .milligram, healthKitIdentifier: "dietaryCaffeine", displayDigits: 0, group: .other)
    ]

    public static let definitions = coreDefinitions + extendedDefinitions
    public static let core = coreDefinitions.map(\.id)

    public static func definition(for id: NutrientID) -> NutrientDefinition? {
        definitions.first { $0.id == id }
    }

    public static func definitions(in group: NutrientGroup) -> [NutrientDefinition] {
        definitions.filter { $0.group == group }
    }
}
