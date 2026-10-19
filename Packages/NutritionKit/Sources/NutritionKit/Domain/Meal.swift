import Foundation

public enum MealType: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        }
    }
}

public struct DiaryEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let dayKey: String
    public let occurredAt: Date
    public let timeZoneIdentifier: String
    public let mealType: MealType
    public let foodID: UUID?
    public let foodName: String
    public let foodNameZh: String?
    public let foodNameEn: String?
    public let quantityDescription: String
    public let quantityDescriptionZh: String?
    public let quantityDescriptionEn: String?
    public let normalizedAmount: Decimal
    public let normalizedUnit: FoodReferenceUnit
    public let nutrients: [NutrientMeasurement]
    public let source: MeasurementSource
    public let photoConfidence: Double?
    public let photoFilenames: [String]
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        dayKey: String,
        occurredAt: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        mealType: MealType,
        foodID: UUID?,
        foodName: String,
        foodNameZh: String? = nil,
        foodNameEn: String? = nil,
        quantityDescription: String,
        quantityDescriptionZh: String? = nil,
        quantityDescriptionEn: String? = nil,
        normalizedAmount: Decimal,
        normalizedUnit: FoodReferenceUnit,
        nutrients: [NutrientMeasurement],
        source: MeasurementSource,
        photoConfidence: Double? = nil,
        photoFilenames: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.dayKey = dayKey
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.mealType = mealType
        self.foodID = foodID
        self.foodName = foodName
        self.foodNameZh = foodNameZh
        self.foodNameEn = foodNameEn
        self.quantityDescription = quantityDescription
        self.quantityDescriptionZh = quantityDescriptionZh
        self.quantityDescriptionEn = quantityDescriptionEn
        self.normalizedAmount = normalizedAmount
        self.normalizedUnit = normalizedUnit
        self.nutrients = nutrients
        self.source = source
        self.photoConfidence = photoConfidence
        self.photoFilenames = photoFilenames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    public func moved(
        to mealType: MealType,
        occurredAt: Date,
        updatedAt: Date = .now
    ) -> DiaryEntry {
        DiaryEntry(
            id: id,
            sessionID: sessionID,
            dayKey: dayKey,
            occurredAt: occurredAt,
            timeZoneIdentifier: timeZoneIdentifier,
            mealType: mealType,
            foodID: foodID,
            foodName: foodName,
            foodNameZh: foodNameZh,
            foodNameEn: foodNameEn,
            quantityDescription: quantityDescription,
            quantityDescriptionZh: quantityDescriptionZh,
            quantityDescriptionEn: quantityDescriptionEn,
            normalizedAmount: normalizedAmount,
            normalizedUnit: normalizedUnit,
            nutrients: nutrients,
            source: source,
            photoConfidence: photoConfidence,
            photoFilenames: photoFilenames,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

public struct DiaryDraft: Codable, Hashable, Sendable {
    public let food: FoodItem
    public let quantity: FoodQuantity
    public let occurredAt: Date
    public let timeZoneIdentifier: String
    public let mealType: MealType
    public let photoConfidence: Double?

    public init(food: FoodItem, quantity: FoodQuantity, occurredAt: Date = .now, timeZoneIdentifier: String = TimeZone.current.identifier, mealType: MealType, photoConfidence: Double? = nil) {
        self.food = food
        self.quantity = quantity
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.mealType = mealType
        self.photoConfidence = photoConfidence
    }
}

public struct NutritionComputation: Codable, Hashable, Sendable {
    public let food: FoodItem
    public let normalizedAmount: Decimal
    public let normalizedUnit: FoodReferenceUnit
    public let nutrients: [NutrientMeasurement]
    public let warnings: [String]

    public init(food: FoodItem, normalizedAmount: Decimal, normalizedUnit: FoodReferenceUnit, nutrients: [NutrientMeasurement], warnings: [String]) {
        self.food = food
        self.normalizedAmount = normalizedAmount
        self.normalizedUnit = normalizedUnit
        self.nutrients = nutrients
        self.warnings = warnings
    }
}

public struct NutrientTotals: Codable, Hashable, Sendable {
    public var values: [NutrientID: NutrientMeasurement]

    public init(values: [NutrientID: NutrientMeasurement] = [:]) {
        self.values = values
    }

    public subscript(_ id: NutrientID) -> NutrientMeasurement? {
        values[id]
    }

    public var energyKcal: Double? { values[NutrientCatalog.energy]?.doubleValue }
}

public struct DailyNutritionSummary: Codable, Hashable, Sendable {
    public let dayKey: String
    public let totals: NutrientTotals
    public let entryCount: Int
    public let hasMissingValues: Bool

    public init(dayKey: String, totals: NutrientTotals, entryCount: Int, hasMissingValues: Bool) {
        self.dayKey = dayKey
        self.totals = totals
        self.entryCount = entryCount
        self.hasMissingValues = hasMissingValues
    }
}

public enum DayKey {
    public static func make(from date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
