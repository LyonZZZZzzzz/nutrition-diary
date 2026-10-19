import Foundation
import Testing
@testable import NutritionKit

struct LocalizationTests {
    @Test
    func resolvesChineseAndEnglishSystemLocales() {
        #expect(AppLanguageResolver.resolve(preference: .system, preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(AppLanguageResolver.resolve(preference: .system, preferredLanguages: ["zh-Hant-TW"]) == .simplifiedChinese)
        #expect(AppLanguageResolver.resolve(preference: .system, preferredLanguages: ["en-US"]) == .english)
        #expect(AppLanguageResolver.resolve(preference: .system, preferredLanguages: ["fr-FR"]) == .english)
        #expect(AppLanguageResolver.resolve(preference: .english, preferredLanguages: ["zh-Hans-CN"]) == .english)
    }

    @Test
    func seedCatalogHasCompleteBilingualNamesAndCategories() {
        #expect(SeedCatalog.foods.count == 121)
        for food in SeedCatalog.foods {
            #expect(food.nameZh?.isEmpty == false)
            #expect(food.nameEn?.isEmpty == false)
            #expect(food.categoryZh?.isEmpty == false)
            #expect(food.categoryEn?.isEmpty == false)
        }
    }

    @Test
    func foodFallsBackToSourceNameWhenTranslationIsMissing() {
        let food = FoodItem(
            name: "USDA source name",
            nameZh: nil,
            nameEn: "USDA source name",
            category: "Rice",
            categoryZh: nil,
            categoryEn: "Rice",
            nutrients: []
        )
        #expect(food.localizedName(for: .simplifiedChinese) == "USDA source name")
        #expect(food.localizedName(for: .english) == "USDA source name")
        #expect(!food.hasLocalizedName(for: .simplifiedChinese))
        #expect(food.hasLocalizedName(for: .english))
    }

    @Test
    func legacyDiaryPayloadDecodesWithoutBilingualSnapshots() throws {
        let entry = DiaryEntry(
            dayKey: "2026-10-17",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            mealType: .lunch,
            foodID: nil,
            foodName: "旧记录",
            quantityDescription: "100 克",
            normalizedAmount: 100,
            normalizedUnit: .gram,
            nutrients: [],
            source: .manual
        )
        let encoded = try JSONEncoder().encode(entry)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "foodNameZh")
        object.removeValue(forKey: "foodNameEn")
        object.removeValue(forKey: "quantityDescriptionZh")
        object.removeValue(forKey: "quantityDescriptionEn")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DiaryEntry.self, from: legacyData)
        #expect(decoded.localizedFoodName(for: .simplifiedChinese) == "旧记录")
        #expect(decoded.localizedFoodName(for: .english) == "旧记录")
        #expect(decoded.localizedQuantityDescription(for: .english) == "100 克")
    }

    @Test
    func englishRelativeTimeAndHealthSourceTextAreLocalized() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(3_661), language: .english) == "Updated 1 hr 1 min ago")
        let source = HealthEnergySource(id: "watch", name: "My Watch", bundleIdentifier: "com.apple.health", isWatch: true)
        #expect(source.localizedDisplayName(for: .english) == "My Watch · Apple Watch")
        #expect(source.localizedDisplayName(for: .simplifiedChinese) == "My Watch · Apple Watch")
    }

    @Test
    func bundledCatalogSearchesEnglishAndChineseWithoutChangingDisplayLanguage() async {
        let catalog = try! #require(SQLiteFoodCatalog.bundled())
        let englishResults = await catalog.searchResults(query: "apple", limit: 20, language: .english)
        let chineseResults = await catalog.searchResults(query: "苹果", limit: 20, language: .simplifiedChinese)
        #expect(englishResults.contains { $0.food.nameEn == "Apple" })
        #expect(chineseResults.first?.food.nameZh == "苹果")

        let chineseEmpty = await catalog.search(query: "", limit: 100, language: .simplifiedChinese)
        #expect(!chineseEmpty.isEmpty)
        #expect(chineseEmpty.allSatisfy { $0.hasLocalizedName(for: .simplifiedChinese) })

        let englishEmpty = await catalog.search(query: "", limit: 100, language: .english)
        #expect(!englishEmpty.isEmpty)
        #expect(englishEmpty.allSatisfy { $0.hasLocalizedName(for: .english) })
    }

    @Test
    func sharedErrorsProvideEnglishDescriptions() {
        let unauthorized = localizedErrorDescription(DeepSeekVisionError.unauthorized, language: .english)
        #expect(unauthorized.contains("invalid"))
        let composite = localizedErrorDescription(CompositeFoodError.invalidYield, language: .english)
        #expect(composite.contains("greater than zero"))
    }
}
