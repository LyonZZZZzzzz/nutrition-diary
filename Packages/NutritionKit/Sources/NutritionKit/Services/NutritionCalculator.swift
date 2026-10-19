import Foundation

public enum NutritionCalculationError: Error, LocalizedError, Sendable {
    case invalidAmount
    case missingDensity
    case unknownPortion
    case incompatibleUnit

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "份量必须大于零"
        case .missingDensity: "该食物缺少密度，无法在克与毫升之间换算"
        case .unknownPortion: "找不到所选份量"
        case .incompatibleUnit: "食物基准单位与录入单位不兼容"
        }
    }
}

public struct NutritionCalculator: Sendable {
    public init() {}

    public func compute(food: FoodItem, quantity: FoodQuantity) throws -> NutritionComputation {
        let normalized = try normalize(food: food, quantity: quantity)
        guard normalized.amount > 0 else { throw NutritionCalculationError.invalidAmount }

        var warnings: [String] = []
        var approximate = normalized.approximate
        if case .purchasedGrams = quantity, food.edibleRatio <= 0 || food.edibleRatio > 1 {
            warnings.append("可食比例异常，已按全部可食处理")
            approximate = true
        }

        let factor = normalized.amount / food.referenceAmount
        let nutrients = food.nutrients.map { measurement -> NutrientMeasurement in
            let status: NutrientStatus
            switch measurement.status {
            case .missing: status = .missing
            case .estimated: status = .estimated
            case .complete: status = approximate ? .estimated : .complete
            }
            return NutrientMeasurement(
                nutrient: measurement.nutrient,
                value: measurement.value.map { $0 * factor },
                unit: measurement.unit,
                status: status,
                source: approximate ? .photoEstimate : measurement.source
            )
        }

        return NutritionComputation(
            food: food,
            normalizedAmount: normalized.amount,
            normalizedUnit: normalized.unit,
            nutrients: nutrients,
            warnings: warnings
        )
    }

    public func summarize(entries: [DiaryEntry], expectedNutrients: [NutrientID] = NutrientCatalog.core) -> DailyNutritionSummary {
        let expectedSet = Set(expectedNutrients)
        var totals: [NutrientID: NutrientMeasurement] = [:]

        for id in expectedNutrients {
            let matching = entries.flatMap { $0.nutrients.filter { $0.nutrient == id } }
            let definition = NutrientCatalog.definition(for: id)
            let unit = definition?.unit ?? .gram

            guard !entries.isEmpty, matching.count == entries.count, matching.allSatisfy({ $0.value != nil }) else {
                totals[id] = .missing(id, unit: unit, source: .manual)
                continue
            }

            let value = matching.compactMap(\.value).reduce(Decimal.zero, +)
            let hasEstimated = matching.contains { $0.status == .estimated }
            totals[id] = NutrientMeasurement(
                nutrient: id,
                value: value,
                unit: unit,
                status: hasEstimated ? .estimated : .complete,
                source: hasEstimated ? .photoEstimate : .manual
            )
        }

        let dayKey = entries.first?.dayKey ?? DayKey.make(from: .now)
        let hasMissing = expectedSet.contains { totals[$0]?.status == .missing }
        return DailyNutritionSummary(dayKey: dayKey, totals: NutrientTotals(values: totals), entryCount: entries.count, hasMissingValues: hasMissing)
    }

    public func compute(recipe: Recipe) throws -> [NutrientMeasurement] {
        var sums: [NutrientID: Decimal] = [:]
        var states: [NutrientID: NutrientStatus] = [:]
        var units: [NutrientID: NutrientUnit] = [:]

        for ingredient in recipe.ingredients {
            let computed = try compute(food: ingredient.food, quantity: ingredient.quantity)
            for measurement in computed.nutrients {
                units[measurement.nutrient] = measurement.unit
                if let value = measurement.value {
                    sums[measurement.nutrient, default: 0] += value
                }
                let current = states[measurement.nutrient] ?? .complete
                if measurement.status == .missing {
                    states[measurement.nutrient] = .missing
                } else if measurement.status == .estimated || current == .estimated {
                    states[measurement.nutrient] = .estimated
                } else if current != .missing {
                    states[measurement.nutrient] = .complete
                }
            }
        }

        return sums.map { nutrient, value in
            NutrientMeasurement(
                nutrient: nutrient,
                value: value,
                unit: units[nutrient] ?? .gram,
                status: states[nutrient] ?? .complete,
                source: recipe.source
            )
        }
        .sorted { $0.nutrient.rawValue < $1.nutrient.rawValue }
    }

    public func normalizedQuantity(food: FoodItem, quantity: FoodQuantity) throws -> (amount: Decimal, unit: FoodReferenceUnit, approximate: Bool) {
        try normalize(food: food, quantity: quantity)
    }

    private func normalize(food: FoodItem, quantity: FoodQuantity) throws -> (amount: Decimal, unit: FoodReferenceUnit, approximate: Bool) {
        switch quantity {
        case .edibleGrams(let grams):
            guard grams > 0 else { throw NutritionCalculationError.invalidAmount }
            return try convertMass(grams, to: food.referenceUnit, density: food.densityGramsPerMilliliter, approximate: false)
        case .purchasedGrams(let grams):
            guard grams > 0 else { throw NutritionCalculationError.invalidAmount }
            let edible = grams * max(0, min(food.edibleRatio, 1))
            return try convertMass(edible, to: food.referenceUnit, density: food.densityGramsPerMilliliter, approximate: food.edibleRatio < 1)
        case .milliliters(let milliliters):
            guard milliliters > 0 else { throw NutritionCalculationError.invalidAmount }
            if food.referenceUnit == .milliliter {
                return (milliliters, .milliliter, false)
            }
            guard let density = food.densityGramsPerMilliliter else { throw NutritionCalculationError.missingDensity }
            return (milliliters * density, .gram, false)
        case .portion(let id, let count):
            guard count > 0 else { throw NutritionCalculationError.invalidAmount }
            guard let portion = food.portion(id: id) else { throw NutritionCalculationError.unknownPortion }
            let amount = portion.amount * count
            let converted = try convertMassOrVolume(amount, from: portion.unit, to: food.referenceUnit, density: food.densityGramsPerMilliliter)
            return (converted, food.referenceUnit, portion.approximate)
        }
    }

    private func convertMass(_ grams: Decimal, to unit: FoodReferenceUnit, density: Decimal?, approximate: Bool) throws -> (Decimal, FoodReferenceUnit, Bool) {
        switch unit {
        case .gram: return (grams, .gram, approximate)
        case .milliliter:
            guard let density, density > 0 else { throw NutritionCalculationError.missingDensity }
            return (grams / density, .milliliter, approximate)
        }
    }

    private func convertMassOrVolume(_ amount: Decimal, from source: FoodReferenceUnit, to target: FoodReferenceUnit, density: Decimal?) throws -> Decimal {
        if source == target { return amount }
        guard let density, density > 0 else { throw NutritionCalculationError.missingDensity }
        switch (source, target) {
        case (.gram, .milliliter): return amount / density
        case (.milliliter, .gram): return amount * density
        default: return amount
        }
    }
}
