import Foundation

public enum CompositeNutritionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case direct
    case recipe

    public var title: String {
        switch self {
        case .direct: "直接营养数据"
        case .recipe: "按配料配方"
        }
    }
}

public struct CompositeFoodDefinition: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var nameZh: String?
    public var nameEn: String?
    public var category: String
    public var categoryZh: String?
    public var categoryEn: String?
    public var mode: CompositeNutritionMode
    public var directReferenceUnit: FoodReferenceUnit
    public var directNutrients: [NutrientMeasurement]
    public var ingredients: [RecipeIngredient]
    public var finalYieldGrams: Decimal?
    public var servings: Decimal
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        nameZh: String? = nil,
        nameEn: String? = nil,
        category: String = "复合食物",
        categoryZh: String? = nil,
        categoryEn: String? = nil,
        mode: CompositeNutritionMode,
        directReferenceUnit: FoodReferenceUnit = .gram,
        directNutrients: [NutrientMeasurement] = [],
        ingredients: [RecipeIngredient] = [],
        finalYieldGrams: Decimal? = nil,
        servings: Decimal = 1,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.category = category
        self.categoryZh = categoryZh
        self.categoryEn = categoryEn
        self.mode = mode
        self.directReferenceUnit = directReferenceUnit
        self.directNutrients = directNutrients
        self.ingredients = ingredients
        self.finalYieldGrams = finalYieldGrams
        self.servings = servings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum CompositeFoodError: Error, LocalizedError, Sendable {
    case missingDirectNutrition
    case missingIngredients
    case invalidYield
    case missingDensity(String)

    public var errorDescription: String? {
        switch self {
        case .missingDirectNutrition: "直接营养数据模式至少需要一个营养值"
        case .missingIngredients: "配方模式至少需要一个食材"
        case .invalidYield: "成品重量或份数必须大于零"
        case .missingDensity(let food): "食材 \(food) 缺少密度，无法换算成品重量"
        }
    }
}

public struct CompositeNutritionCalculator: Sendable {
    private let calculator = NutritionCalculator()

    public init() {}

    public func foodItem(from composite: CompositeFoodDefinition) throws -> FoodItem {
        switch composite.mode {
        case .direct:
            guard composite.directNutrients.contains(where: { $0.value != nil }) else {
                throw CompositeFoodError.missingDirectNutrition
            }
            return FoodItem(
                id: composite.id,
                name: composite.name,
                nameZh: composite.nameZh,
                nameEn: composite.nameEn,
                category: composite.category,
                categoryZh: composite.categoryZh,
                categoryEn: composite.categoryEn,
                referenceAmount: 100,
                referenceUnit: composite.directReferenceUnit,
                nutrients: composite.directNutrients,
                source: FoodSource(
                    kind: .custom,
                    identifier: "composite.\(composite.id.uuidString)",
                    title: "直接营养数据",
                    titleZh: "直接营养数据",
                    titleEn: "Direct nutrition data",
                    retrievedAt: composite.updatedAt
                )
            )
        case .recipe:
            let per100 = try per100Nutrients(composite)
            let portions: [ServingPortion]
            if let yield = composite.finalYieldGrams, composite.servings > 0 {
                portions = [ServingPortion(label: "1份", labelZh: "1 份", labelEn: "1 serving", amount: yield / composite.servings, unit: .gram, approximate: true)]
            } else {
                portions = []
            }
            return FoodItem(
                id: composite.id,
                name: composite.name,
                nameZh: composite.nameZh,
                nameEn: composite.nameEn,
                category: composite.category,
                categoryZh: composite.categoryZh,
                categoryEn: composite.categoryEn,
                referenceAmount: 100,
                referenceUnit: .gram,
                nutrients: per100,
                portions: portions,
                source: FoodSource(
                    kind: .custom,
                    identifier: "composite.\(composite.id.uuidString)",
                    title: "配方计算（\(composite.ingredients.count) 种食材）",
                    titleZh: "配方计算（\(composite.ingredients.count) 种食材）",
                    titleEn: "Recipe calculation (\(composite.ingredients.count) ingredients)",
                    retrievedAt: composite.updatedAt
                )
            )
        }
    }

    public func per100Nutrients(_ composite: CompositeFoodDefinition) throws -> [NutrientMeasurement] {
        guard composite.mode == .recipe else {
            return composite.directNutrients
        }
        guard !composite.ingredients.isEmpty else { throw CompositeFoodError.missingIngredients }
        guard composite.servings > 0 else { throw CompositeFoodError.invalidYield }

        var totalWeight: Decimal = 0
        var totals: [NutrientID: Decimal] = [:]
        var states: [NutrientID: NutrientStatus] = [:]
        var units: [NutrientID: NutrientUnit] = [:]
        var foodNames: [NutrientID: [String]] = [:]

        for ingredient in composite.ingredients {
            let normalized = try calculator.normalizedQuantity(food: ingredient.food, quantity: ingredient.quantity)
            let grams: Decimal
            switch normalized.unit {
            case .gram:
                grams = normalized.amount
            case .milliliter:
                guard let density = ingredient.food.densityGramsPerMilliliter else {
                    throw CompositeFoodError.missingDensity(ingredient.food.name)
                }
                grams = normalized.amount * density
            }
            totalWeight += grams

            let computed = try calculator.compute(food: ingredient.food, quantity: ingredient.quantity)
            for measurement in computed.nutrients {
                units[measurement.nutrient] = measurement.unit
                foodNames[measurement.nutrient, default: []].append(ingredient.food.name)
                if let value = measurement.value {
                    totals[measurement.nutrient, default: 0] += value
                }
                if measurement.status == .missing {
                    states[measurement.nutrient] = .missing
                } else if measurement.status == .estimated || states[measurement.nutrient] == .estimated {
                    states[measurement.nutrient] = .estimated
                } else if states[measurement.nutrient] != .missing {
                    states[measurement.nutrient] = .complete
                }
            }
        }

        let yield = composite.finalYieldGrams ?? totalWeight
        guard yield > 0 else { throw CompositeFoodError.invalidYield }
        let factor = Decimal(100) / yield
        let yieldEstimated = composite.finalYieldGrams == nil

        let expected = Set(NutrientCatalog.core).union(totals.keys)
        return expected.compactMap { nutrient -> NutrientMeasurement? in
            guard let unit = units[nutrient] else { return nil }
            let value = totals[nutrient]
            let ingredientsWithNutrient = foodNames[nutrient]?.count ?? 0
            let completeAcrossIngredients = ingredientsWithNutrient == composite.ingredients.count
            let status: NutrientStatus
            if value == nil || !completeAcrossIngredients || states[nutrient] == .missing {
                status = .missing
            } else if yieldEstimated || states[nutrient] == .estimated {
                status = .estimated
            } else {
                status = .complete
            }
            return NutrientMeasurement(
                nutrient: nutrient,
                value: status == .missing ? nil : value.map { $0 * factor },
                unit: unit,
                status: status,
                source: status == .estimated ? .photoEstimate : .recipe
            )
        }
        .sorted { $0.nutrient.rawValue < $1.nutrient.rawValue }
    }
}
