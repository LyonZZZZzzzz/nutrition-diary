import Foundation
import Testing
@testable import NutritionKit

struct FullCatalogLocalizationTests {
    @Test
    func everyBundledFoodHasChineseNameAndLocalizationOrigin() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let manifest = try #require(CatalogManifest.bundled())
        let foods = await catalog.search(query: "", limit: 20_000, language: .simplifiedChinese)

        #expect(foods.count == manifest.recordCount)
        #expect(manifest.nameZhCount == manifest.recordCount)
        #expect(manifest.nameZhMissingCount == 0)
        #expect(foods.allSatisfy { $0.nameZh?.isEmpty == false })
        #expect(foods.allSatisfy { $0.nameZhOrigin != nil })
        #expect(foods.allSatisfy { $0.nameZh?.range(of: "[\\u3400-\\u9fff]", options: .regularExpression) != nil })
    }

    @Test
    func localizationOriginsCoverEveryRecordExactlyOnce() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let manifest = try #require(CatalogManifest.bundled())
        let foods = await catalog.search(query: "", limit: 20_000, language: .simplifiedChinese)
        let curated = foods.filter { $0.nameZhOrigin == .curated }.count
        let taiwan = foods.filter { $0.nameZhOrigin == .taiwanFDA }.count
        let machine = foods.filter { $0.nameZhOrigin == .localMachineTranslation }.count
        let original = foods.filter { $0.nameZhOrigin == .original }.count

        #expect(curated == manifest.nameZhCuratedCount)
        #expect(taiwan == manifest.nameZhTaiwanCount)
        #expect(machine == manifest.nameZhMachineCount)
        #expect(curated + taiwan + machine + original == manifest.recordCount)
    }

    @Test
    func sourceTitlesAreNotAccidentallyReplacedByPortionLabels() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let foods = await catalog.search(query: "", limit: 20_000, language: .simplifiedChinese)
        let invalidTitles = Set(["oz", "cup", "1 cup", "fl oz", "tbsp", "serving", "1份", "lb", "slice", "piece"])
        #expect(foods.allSatisfy { !invalidTitles.contains($0.source.title) })
        #expect(foods.allSatisfy {
            $0.source.title.contains("USDA")
                || $0.source.title.contains("FoodData")
                || $0.source.title.contains("Open Food Facts")
                || $0.source.title.contains("NutritionDiary")
        })
    }

    @Test
    func machineTranslationsCoverExpectedFoodTermsAndPreserveBrands() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())

        let bigMac = await catalog.searchResults(query: "巨无霸", limit: 20, language: .simplifiedChinese)
        #expect(bigMac.contains { $0.food.nameZh?.contains("巨无霸") == true })
        #expect(bigMac.contains { $0.food.nameZh?.localizedCaseInsensitiveContains("McDONALD") == true })

        let sirloin = await catalog.searchResults(query: "西冷牛排", limit: 20, language: .simplifiedChinese)
        #expect(!sirloin.isEmpty)

        let grapeTomato = await catalog.searchResults(query: "圣女果", limit: 20, language: .simplifiedChinese)
        #expect(grapeTomato.contains { $0.food.name == "Tomatoes, grape, raw" })

        let appleInEnglish = await catalog.searchResults(query: "apple", limit: 20, language: .english)
        #expect(appleInEnglish.contains { $0.food.nameEn == "Apple" })
    }

    @Test
    func translationCacheIsCompleteAndVersioned() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("CatalogData/FoodNameZhTranslations.json")
        let data = try Data(contentsOf: url)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(object["entries"] as? [String: [String: Any]])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["sourceLanguage"] as? String == "en")
        #expect(object["targetLanguage"] as? String == "zh-Hans")
        #expect(entries.count == 13_388)
        let manifest = try #require(CatalogManifest.bundled())
        #expect(manifest.translationCacheVersion == 1)
        #expect(manifest.translationCacheSHA256?.isEmpty == false)
        #expect(manifest.translationSourceSHA256 == object["sourceSHA256"] as? String)
        #expect(entries.values.allSatisfy { value in
            guard let name = value["nameZh"] as? String, !name.isEmpty else { return false }
            return name.range(of: "[\\u3400-\\u9fff]", options: .regularExpression) != nil
        })
    }
}
