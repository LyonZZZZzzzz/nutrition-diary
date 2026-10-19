import Foundation

public enum SeedCatalog {
    public static let foods: [FoodItem] = loadFoods()

    private static func loadFoods() -> [FoodItem] {
        guard let url = Bundle.module.url(forResource: "SeedFoods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(SeedCatalogFile.self, from: data) else {
            assertionFailure("SeedFoods.json is missing or invalid")
            return []
        }
        let overlayURL = Bundle.module.url(forResource: "FoodLocalizationOverlay", withExtension: "json")
        let overlay = overlayURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(FoodLocalizationOverlay.self, from: $0) }
        let foodsByID = Dictionary(uniqueKeysWithValues: overlay?.foods.map { ($0.id, $0) } ?? [])
        return catalog.foods.map { $0.foodItem(overlay: foodsByID[$0.uuid], localization: overlay) }
    }
}

private struct SeedCatalogFile: Decodable {
    let schemaVersion: Int
    let catalogVersion: String
    let foods: [SeedFoodRecord]
}

private struct SeedFoodRecord: Decodable {
    let uuid: String
    let name: String
    let aliases: [String]
    let category: String
    let referenceAmount: Decimal
    let referenceUnit: FoodReferenceUnit
    let edibleRatio: Decimal
    let densityGramsPerMilliliter: Decimal?
    let portions: [SeedPortionRecord]
    let nutrients: [String: Decimal]
    let estimatedNutrients: [String]
    let source: SeedSourceRecord

    func foodItem(overlay: OverlayFood?, localization: FoodLocalizationOverlay?) -> FoodItem {
        let definitions = Dictionary(uniqueKeysWithValues: NutrientCatalog.definitions.map { ($0.id.rawValue, $0) })
        let estimated = Set(estimatedNutrients)
        let measurements = nutrients.compactMap { key, value -> NutrientMeasurement? in
            guard let definition = definitions[key] else { return nil }
            return NutrientMeasurement(
                nutrient: definition.id,
                value: value,
                unit: definition.unit,
                status: estimated.contains(key) ? .estimated : .complete,
                source: estimated.contains(key) ? .manual : .bundledCatalog
            )
        }
        return FoodItem(
            id: UUID(uuidString: uuid) ?? UUID(),
            name: name,
            nameZh: overlay?.nameZh ?? name,
            nameEn: overlay?.nameEn,
            nameZhOrigin: .curated,
            aliases: aliases,
            category: category,
            categoryZh: overlay?.categoryZh ?? category,
            categoryEn: overlay?.categoryEn ?? localization?.categories[category],
            referenceAmount: referenceAmount,
            referenceUnit: referenceUnit,
            edibleRatio: edibleRatio,
            densityGramsPerMilliliter: densityGramsPerMilliliter,
            nutrients: measurements,
            portions: portions.map {
                ServingPortion(
                    label: $0.label,
                    labelZh: $0.label,
                    labelEn: localization?.portionLabels[$0.label],
                    amount: $0.amount,
                    unit: $0.unit,
                    approximate: $0.approximate
                )
            },
            source: FoodSource(
                kind: source.kind,
                identifier: source.identifier,
                title: source.title,
                titleZh: source.title,
                titleEn: localization?.sourceTitles[source.title],
                license: source.license,
                sourceURL: source.url.flatMap(URL.init(string:)),
                retrievedAt: source.retrievedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            )
        )
    }
}

private struct SeedPortionRecord: Decodable {
    let label: String
    let amount: Decimal
    let unit: FoodReferenceUnit
    let approximate: Bool
}

private struct SeedSourceRecord: Decodable {
    let kind: FoodSourceKind
    let identifier: String?
    let title: String
    let license: String?
    let url: String?
    let retrievedAt: String?
}


private struct FoodLocalizationOverlay: Decodable {
    let schemaVersion: Int
    let catalogVersion: String
    let categories: [String: String]
    let portionLabels: [String: String]
    let sourceTitles: [String: String]
    let foods: [OverlayFood]
}

private struct OverlayFood: Decodable {
    let id: String
    let nameZh: String?
    let nameEn: String?
    let categoryZh: String?
    let categoryEn: String?
}
